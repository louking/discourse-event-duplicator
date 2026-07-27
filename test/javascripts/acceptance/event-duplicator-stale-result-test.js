import { click, currentURL, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

const ALLOWED_CATEGORY = {
  id: 400,
  name: "racing-events",
  slug: "racing-events",
  permission: 1, // PermissionType.FULL -- guardian.can_create_topic_on_category?
  topic_count: 1,
};

// The backend's `already_duplicated`/`existing_duplicate_topic_url` reflect
// DuplicationTracker's live state -- not duplicated, in this fixture, the
// same as it would be right after the earlier duplicate got deleted (which
// frees the source back up via DuplicationTracker#forget!, see plugin.rb's
// :topic_trashed hook).
const NOT_DUPLICATED = {
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

// Regression coverage for GitHub issue #16 ("after deleting duplicated
// events, /review page shows that the events remain duplicated"). The
// controller's `result` (set by `confirmDuplication`, see
// controllers/event-duplicator.js) marks a row "duplicated to topic" for the
// rest of the browser session, since it's never nulled out after a
// successful confirm -- that's deliberate, so a reviewer's own "Duplicate
// selected" click keeps showing the link without needing a refetch. But
// because `controller:event-duplicator` is a singleton, that same `result`
// used to survive a genuine return trip to the route too. Delete the
// duplicate topic (DuplicationTracker#forget! frees the source back up) and
// revisit the review page -- the fresh `already_duplicated: false` from the
// backend should win, not the stale in-session "just duplicated" state.
acceptance(
  "Event Duplicator - stale result after revisiting",
  function (needs) {
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
      server.get("/event-duplicator/topics/9001/proposed_dates", () => {
        return helper.response(NOT_DUPLICATED);
      });

      server.post("/event-duplicator/duplicate", () => {
        return helper.response({
          duplicated: [
            { topic_id: 9001, new_topic_id: 42, new_topic_url: "/t/42" },
          ],
          skipped: [],
        });
      });
    });

    test("a row's 'duplicated to topic' link clears once the route is revisited and the backend no longer reports it duplicated", async function (assert) {
      await visit("/event-duplicator/review?topic_id=9001");

      assert
        .dom(".event-duplicator-already-duplicated")
        .doesNotExist("not flagged as duplicated before confirming");

      await click(".btn-primary");

      assert
        .dom(".event-duplicator-already-duplicated a")
        .hasAttribute(
          "href",
          "/t/42",
          "shows the just-duplicated link immediately after confirming"
        );

      // Leave the route entirely, then come back -- a genuine re-entry, same
      // as a user navigating to the duplicate topic (to delete it) and
      // returning, not just a re-render.
      await visit("/latest");
      await visit("/event-duplicator/review?topic_id=9001");

      assert.strictEqual(
        currentURL(),
        "/event-duplicator/review?topic_id=9001"
      );
      assert
        .dom(".event-duplicator-already-duplicated")
        .doesNotExist(
          "stale session state no longer overrides the fresh backend flag"
        );
      assert.dom("tbody input[type=checkbox]").isNotDisabled();
    });
  }
);
