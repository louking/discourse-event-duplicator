import { click, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

const PROPOSED_DATES = {
  topic_id: 9001,
  title: "Grand Prix",
  original_start: "2026-07-04T18:00:00.000Z",
  original_end: "2026-07-04T20:00:00.000Z",
  proposed_start: "2027-07-04T18:00:00.000Z",
  proposed_end: "2027-07-04T20:00:00.000Z",
  already_duplicated: false,
  existing_duplicate_topic_id: null,
  existing_duplicate_topic_url: null,
};

// The "Skipped:" panel in templates/event-duplicator.hbs had no coverage --
// result.skipped's *shape* is unit-tested on the controller
// (unit/controllers/event-duplicator-test.js), but nothing asserted the
// panel itself renders, or that it picks the right branch (a link for an
// already-duplicated skip vs. plain reason text for anything else).
//
// Both scenarios below are real, not hypothetical: `force` is computed
// client-side from whatever the review page's model looked like when it
// loaded (see controllers/event-duplicator.js), so a stale review tab --
// two browser tabs, two admins reviewing overlapping series tags (a topic
// can carry more than one), or just a long review session left open while
// someone else duplicates that topic elsewhere -- sends `force: false` and
// gets skipped for real. A non-duplicate skip (e.g. "unauthorized") is
// rarer but equally real: a group membership or category permission
// changed out from under an already-open review page.
//
// Neither race needs to be reproduced here, though -- the frontend only
// reacts to whatever JSON `POST /event-duplicator/duplicate` returns, so
// pretender stands in for the backend, same as
// event-duplicator-duplicate-request-test.js does for the request shape.
acceptance(
  "Event Duplicator - skipped panel (already duplicated)",
  function (needs) {
    needs.user({
      can_create_discourse_post_event: true,
      groups: [{ id: 3, name: "staff" }],
    });
    needs.settings({
      event_duplicator_enabled: true,
      event_duplicator_allowed_groups: "3",
    });

    needs.pretender((server, helper) => {
      server.get("/event-duplicator/topics/9001/proposed_dates", () => {
        return helper.response(PROPOSED_DATES);
      });

      server.post("/event-duplicator/duplicate", () => {
        return helper.response({
          duplicated: [],
          skipped: [
            {
              topic_id: 9001,
              reason: "already_duplicated",
              existing_duplicate_topic_id: 9099,
              existing_duplicate_topic_url: "/t/9099",
            },
          ],
        });
      });
    });

    test("renders a link to the existing duplicate instead of the raw reason", async function (assert) {
      await visit("/event-duplicator/review?topic_id=9001");
      await click(".btn-primary");

      assert
        .dom(".event-duplicator-result")
        .exists("the skipped panel renders");
      assert
        .dom(".event-duplicator-result")
        .includesText("Skipped:", "shows the skipped heading");
      assert
        .dom(".event-duplicator-result a")
        .hasAttribute(
          "href",
          "/t/9099",
          "links to the duplicate that beat this submission"
        );
      assert
        .dom(".event-duplicator-result")
        .doesNotIncludeText(
          "already_duplicated",
          "the raw reason string isn't shown when a duplicate link is available"
        );
    });
  }
);

acceptance(
  "Event Duplicator - skipped panel (other failure reasons)",
  function (needs) {
    needs.user({
      can_create_discourse_post_event: true,
      groups: [{ id: 3, name: "staff" }],
    });
    needs.settings({
      event_duplicator_enabled: true,
      event_duplicator_allowed_groups: "3",
    });

    needs.pretender((server, helper) => {
      server.get("/event-duplicator/topics/9001/proposed_dates", () => {
        return helper.response(PROPOSED_DATES);
      });

      server.post("/event-duplicator/duplicate", () => {
        return helper.response({
          duplicated: [],
          skipped: [{ topic_id: 9001, reason: "unauthorized" }],
        });
      });
    });

    test("renders the raw reason text, not a link, when there's no existing duplicate to point at", async function (assert) {
      await visit("/event-duplicator/review?topic_id=9001");
      await click(".btn-primary");

      assert
        .dom(".event-duplicator-result")
        .exists("the skipped panel renders");
      assert
        .dom(".event-duplicator-result")
        .includesText("unauthorized", "shows the raw reason");
      assert
        .dom(".event-duplicator-result a")
        .doesNotExist("no duplicate link is rendered for a non-duplicate skip");
    });
  }
);
