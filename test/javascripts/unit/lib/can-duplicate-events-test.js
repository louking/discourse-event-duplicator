import { module, test } from "qunit";
import { canDuplicateEvents } from "discourse/plugins/discourse-event-duplicator/discourse/lib/can-duplicate-events";

// Group membership itself is decided server-side (the
// `event_duplicator_in_allowed_groups` current_user attribute in plugin.rb);
// its cases are covered in spec/serializers/current_user_serializer_spec.rb.
function user(overrides = {}) {
  return {
    can_create_discourse_post_event: true,
    event_duplicator_in_allowed_groups: true,
    ...overrides,
  };
}

function siteSettings(overrides = {}) {
  return {
    event_duplicator_enabled: true,
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

  test("false when the server says the user isn't in an allowed group", function (assert) {
    assert.false(
      canDuplicateEvents(
        user({ event_duplicator_in_allowed_groups: false }),
        siteSettings()
      )
    );
  });

  test("false when the attribute is missing entirely", function (assert) {
    assert.false(
      canDuplicateEvents(
        user({ event_duplicator_in_allowed_groups: undefined }),
        siteSettings()
      )
    );
  });

  test("true when every check passes", function (assert) {
    assert.true(canDuplicateEvents(user(), siteSettings()));
  });
});
