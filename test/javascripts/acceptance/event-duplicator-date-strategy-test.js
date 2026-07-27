import { click, currentURL, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { cloneJSON } from "discourse/lib/object";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";
import topicFixtures from "discourse/tests/fixtures/topic";

const ALLOWED_CATEGORY = {
  id: 400,
  name: "racing-events",
  slug: "racing-events",
  permission: 1, // PermissionType.FULL -- guardian.can_create_topic_on_category?
  topic_count: 1,
};

const PROPOSED_DATES = {
  topic_id: 9001,
  title: "Community Meetup",
  original_start: "2026-03-01T18:00:00.000Z",
  original_end: "2026-03-01T20:00:00.000Z",
  proposed_start: "2027-03-01T18:00:00.000Z",
  proposed_end: "2027-03-01T20:00:00.000Z",
  already_duplicated: false,
  existing_duplicate_topic_id: null,
  existing_duplicate_topic_url: null,
};

// Regression coverage for GitHub issue #13 ("duplicated single event, saw
// wrong date in review form"). Two real bugs combined to produce that
// report:
//
// 1. The Date rule <select> bound `value={{this.model.dateStrategy}}`
//    directly on the <select> element. Glimmer sets that as a DOM property,
//    but does so while the <select>'s opening tag is flushed -- before its
//    <option> children exist in the DOM -- so the assignment had no visible
//    effect, and the browser always fell back to selecting the first
//    <option> ("Same calendar date") regardless of the real active
//    strategy. See the `isCalendarDateStrategy`/`isNthWeekdayOfMonthStrategy`
//    getters in controllers/event-duplicator.js.
// 2. Clicking the topic-admin "Duplicate event" button explicitly clears
//    series-mode-only query params (`category_id`/`tags`/`starts_after`/
//    `starts_before`) left over from an earlier visit, but used to leave
//    `date_strategy` out of that list -- so a rule picked on an earlier
//    visit silently carried over and was used to compute the next single
//    topic's proposed date instead of the intended default.
acceptance("Event Duplicator - date rule dropdown", function (needs) {
  needs.user({
    can_create_discourse_post_event: true,
    groups: [{ id: 3, name: "staff" }],
  });
  needs.settings({
    event_duplicator_enabled: true,
    event_duplicator_allowed_groups: "3",
  });
  needs.site({ categories: [ALLOWED_CATEGORY] });

  needs.pretender((server, helper) => {
    server.get("/t/9001.json", () => {
      const topic = cloneJSON(topicFixtures["/t/9/1.json"]);
      topic.id = 9001;
      topic.slug = "community-meetup";
      topic.category_id = ALLOWED_CATEGORY.id;
      topic.event_duplicator_has_event = true;
      return helper.response(topic);
    });

    server.get("/event-duplicator/topics/9001/proposed_dates", () => {
      return helper.response(PROPOSED_DATES);
    });
  });

  test("shows the actual active strategy as selected, not always the first option", async function (assert) {
    await visit(
      "/event-duplicator/review?topic_id=9001&date_strategy=nth_weekday_of_month"
    );

    assert
      .dom(".event-duplicator-date-strategy select")
      .hasValue("nth_weekday_of_month");
  });

  test("defaults to the calendar_date option when no strategy override is active", async function (assert) {
    await visit("/event-duplicator/review?topic_id=9001");

    assert
      .dom(".event-duplicator-date-strategy select")
      .hasValue("calendar_date");
  });

  test("a date rule picked on an earlier visit doesn't leak into a later topic-admin duplication", async function (assert) {
    await visit(
      "/event-duplicator/review?topic_id=9001&date_strategy=nth_weekday_of_month"
    );

    await visit("/t/community-meetup/9001");
    await click(".toggle-admin-menu");
    await click(".event-duplicator-duplicate-topic");

    assert.notOk(
      currentURL().includes("date_strategy="),
      "the stale date_strategy query param was cleared"
    );
    assert
      .dom(".event-duplicator-date-strategy select")
      .hasValue(
        "calendar_date",
        "the review page falls back to the site default strategy, not the stale one"
      );
  });
});
