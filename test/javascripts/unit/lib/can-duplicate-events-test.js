import { module, test } from "qunit";
import { canDuplicateEvents } from "discourse/plugins/discourse-event-duplicator/discourse/lib/can-duplicate-events";

function user(overrides = {}) {
  return {
    can_create_discourse_post_event: true,
    groups: [{ id: 3 }],
    ...overrides,
  };
}

function siteSettings(overrides = {}) {
  return {
    event_duplicator_enabled: true,
    event_duplicator_allowed_groups: "3",
    ...overrides,
  };
}

module("Unit | Lib | can-duplicate-events", function () {
  test("false when there is no current user", function (assert) {
    assert.false(canDuplicateEvents(null, siteSettings()));
  });

  test("false when event_duplicator_enabled is off, even for an otherwise-eligible user -- the JS bundle itself isn't unloaded by toggling a client:true setting, so the frontend must check it explicitly", function (assert) {
    assert.false(
      canDuplicateEvents(
        user(),
        siteSettings({ event_duplicator_enabled: false })
      )
    );
  });

  test("false when discourse-calendar itself disallows the user", function (assert) {
    assert.false(
      canDuplicateEvents(
        user({ can_create_discourse_post_event: false }),
        siteSettings()
      )
    );
  });

  test("false when event_duplicator_allowed_groups is empty (nobody passes, not unrestricted)", function (assert) {
    assert.false(
      canDuplicateEvents(
        user(),
        siteSettings({ event_duplicator_allowed_groups: "" })
      )
    );
  });

  test("false when the user belongs to none of the allowed groups", function (assert) {
    assert.false(
      canDuplicateEvents(
        user({ groups: [{ id: 14 }] }),
        siteSettings({ event_duplicator_allowed_groups: "3|5" })
      )
    );
  });

  test("true when the user belongs to one of several allowed groups", function (assert) {
    assert.true(
      canDuplicateEvents(
        user({ groups: [{ id: 1 }, { id: 5 }] }),
        siteSettings({ event_duplicator_allowed_groups: "3|5" })
      )
    );
  });

  test("true when the allowed groups list includes the everyone auto-group -- relies on every real user's groups already including id 0, there's no special-casing for it", function (assert) {
    assert.true(
      canDuplicateEvents(
        user({ groups: [{ id: 0 }, { id: 14 }] }),
        siteSettings({ event_duplicator_allowed_groups: "0" })
      )
    );
  });
});
