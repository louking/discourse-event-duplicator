import { click, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

// Regression test for a real bug (see CLAUDE.md): `services/event-duplicator.js`'s
// `duplicate()` used to send `data: { items }` without an explicit
// `contentType`, so `ajax()` (a thin `$.ajax` wrapper with no default
// contentType) fell back to jQuery's form-urlencoded serialization, which
// encodes an array of objects as indexed bracket params
// (`items[0][topic_id]=...`). Rails parsed that shape into a Hash keyed by
// the string "0", not an Array, so every `topic_id` read back as `nil` and
// every duplication 404'd. Every other test in this suite stubs
// `eventDuplicator.duplicate()` itself, which never exercises the real
// `ajax()` call this bug lived in -- this test goes through the real
// service, asserting on the actual intercepted request.
acceptance("Event Duplicator - duplicate request body", function (needs) {
  needs.user({
    can_create_discourse_post_event: true,
    groups: [{ id: 3, name: "staff" }],
  });
  needs.settings({
    event_duplicator_enabled: true,
    event_duplicator_allowed_groups: "3",
  });

  let capturedRequest;

  needs.pretender((server, helper) => {
    server.get("/event-duplicator/topics/9001/proposed_dates", () => {
      return helper.response({
        topic_id: 9001,
        title: "Grand Prix",
        original_start: "2026-07-04T18:00:00.000Z",
        original_end: "2026-07-04T20:00:00.000Z",
        proposed_start: "2027-07-04T18:00:00.000Z",
        proposed_end: "2027-07-04T20:00:00.000Z",
        already_duplicated: false,
        existing_duplicate_topic_id: null,
        existing_duplicate_topic_url: null,
      });
    });

    server.post("/event-duplicator/duplicate", (request) => {
      capturedRequest = request;
      return helper.response({
        duplicated: [
          { topic_id: 9001, new_topic_id: 9099, new_topic_url: "/t/9099" },
        ],
        skipped: [],
      });
    });
  });

  test("sends the duplicate request as real JSON, with topic_id intact, not form-encoded", async function (assert) {
    await visit("/event-duplicator/review?topic_id=9001");
    await click(".btn-primary");

    assert.ok(capturedRequest, "the duplicate request was sent");
    assert.true(
      capturedRequest.requestHeaders["Content-Type"].includes(
        "application/json"
      ),
      "Content-Type is application/json, not form-urlencoded"
    );

    const body = JSON.parse(capturedRequest.requestBody);
    assert.true(Array.isArray(body.items), "items is a real JSON array");
    assert.strictEqual(
      body.items[0].topic_id,
      9001,
      "topic_id survives serialization intact -- this is exactly what broke under form-encoding"
    );
  });
});
