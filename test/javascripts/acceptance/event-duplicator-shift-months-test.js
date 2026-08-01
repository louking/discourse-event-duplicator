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

// Regression coverage for GitHub issue #19 ("add n months shift support"),
// following the same shape as event-duplicator-date-strategy-test.js since
// `shift_months` is wired through the exact same query-param path as
// `date_strategy` (and is vulnerable to the same class of stale-param
// carryover bug fixed there for GitHub issue #13).
acceptance("Event Duplicator - shift months input", function (needs) {
  needs.user({
    can_create_discourse_post_event: true,
    groups: [{ id: 3, name: "staff" }],
  });
  needs.settings({
    event_duplicator_enabled: true,
    event_duplicator_allowed_groups: "3",
    event_duplicator_default_shift_months: 12,
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

  test("shows the actual active shift_months value, not always the site default", async function (assert) {
    await visit("/event-duplicator/review?topic_id=9001&shift_months=3");

    assert.dom(".event-duplicator-shift-months input").hasValue("3");
  });

  test("defaults to the site setting when no shift_months override is active", async function (assert) {
    await visit("/event-duplicator/review?topic_id=9001");

    assert.dom(".event-duplicator-shift-months input").hasValue("12");
  });

  test("a shift picked on an earlier visit doesn't leak into a later topic-admin duplication", async function (assert) {
    await visit("/event-duplicator/review?topic_id=9001&shift_months=3");

    await visit("/t/community-meetup/9001");
    await click(".toggle-admin-menu");
    await click(".event-duplicator-duplicate-topic");

    assert.notOk(
      currentURL().includes("shift_months="),
      "the stale shift_months query param was cleared"
    );
    assert
      .dom(".event-duplicator-shift-months input")
      .hasValue(
        "12",
        "the review page falls back to the site default shift, not the stale one"
      );
  });
});
