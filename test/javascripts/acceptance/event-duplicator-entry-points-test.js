import { click, currentURL, visit } from "@ember/test-helpers";
import { test } from "qunit";
import { cloneJSON } from "discourse/lib/object";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";
import topicFixtures from "discourse/tests/fixtures/topic";

const SIDEBAR_LINK = ".sidebar-section-link[data-link-name='event-duplicator']";

const ALLOWED_CATEGORY = {
  id: 400,
  name: "racing-events",
  slug: "racing-events",
  permission: 1, // PermissionType.FULL -- guardian.can_create_topic_on_category?
  topic_count: 1,
};

const READ_ONLY_CATEGORY = {
  ...ALLOWED_CATEGORY,
  id: 401,
  slug: "read-only-events",
  permission: 2, // PermissionType.CREATE_POST -- can reply, can't create topics
};

function withTopicPage(
  needs,
  { id, category, proposedDates, hasEvent = true, moderationCapable = true }
) {
  needs.pretender((server, helper) => {
    server.get(`/t/${id}.json`, () => {
      const topic = cloneJSON(topicFixtures["/t/9/1.json"]);
      topic.id = id;
      topic.slug = "grand-prix";
      topic.category_id = category.id;
      topic.event_duplicator_has_event = hasEvent;
      // The shared fixture hardcodes these to true regardless of the
      // simulated user. Discourse core's own TopicAdminMenu#showAdminButton
      // gates the entire wrench menu (including any button this plugin adds
      // via addTopicAdminMenuButton) on canManageTopic (staff/TL4) or these
      // moderator-only flags -- a real 4th permission on top of this
      // plugin's own three checks. See GitHub issue #11.
      topic.details.can_close_topic = moderationCapable;
      topic.details.can_archive_topic = moderationCapable;
      topic.details.can_split_merge_topic = moderationCapable;
      return helper.response(topic);
    });

    if (proposedDates) {
      server.get(`/event-duplicator/topics/${id}/proposed_dates`, () => {
        return helper.response(proposedDates);
      });
    }
  });
}

acceptance("Event Duplicator - entry points (allowed user)", function (needs) {
  needs.user({
    can_create_discourse_post_event: true,
    groups: [{ id: 3, name: "staff" }],
  });
  needs.settings({
    event_duplicator_enabled: true,
    event_duplicator_allowed_groups: "3",
  });
  needs.site({ categories: [ALLOWED_CATEGORY] });
  withTopicPage(needs, {
    id: 9001,
    category: ALLOWED_CATEGORY,
    proposedDates: {
      topic_id: 9001,
      title: "Grand Prix",
      original_start: "2026-07-04T18:00:00.000Z",
      original_end: "2026-07-04T20:00:00.000Z",
      proposed_start: "2027-07-04T18:00:00.000Z",
      proposed_end: "2027-07-04T20:00:00.000Z",
      already_duplicated: false,
      existing_duplicate_topic_id: null,
      existing_duplicate_topic_url: null,
    },
  });

  test("sidebar link is shown and points at the picker page", async function (assert) {
    await visit("/");

    assert.dom(SIDEBAR_LINK).exists();
    await click(SIDEBAR_LINK);
    assert.strictEqual(currentURL(), "/event-duplicator/new");
  });

  test("topic-admin menu button is shown on a topic in a category the user can create topics in", async function (assert) {
    await visit("/t/grand-prix/9001");
    await click(".toggle-admin-menu");

    assert.dom(".event-duplicator-duplicate-topic").exists();
  });

  test("clicking the topic-admin button routes straight to the review page for that topic, with series-mode params cleared", async function (assert) {
    await visit("/t/grand-prix/9001");
    await click(".toggle-admin-menu");
    await click(".event-duplicator-duplicate-topic");

    assert.ok(currentURL().startsWith("/event-duplicator/review"));
    assert.ok(currentURL().includes("topic_id=9001"));
    assert.notOk(currentURL().includes("category_id="));
    assert.notOk(currentURL().includes("tags="));
  });
});

acceptance(
  "Event Duplicator - entry points (event_duplicator_enabled off)",
  function (needs) {
    needs.user({
      admin: true,
      can_create_discourse_post_event: true,
      groups: [{ id: 3, name: "staff" }],
    });
    needs.settings({
      event_duplicator_enabled: false,
      event_duplicator_allowed_groups: "3",
    });
    needs.site({ categories: [ALLOWED_CATEGORY] });
    withTopicPage(needs, { id: 9002, category: ALLOWED_CATEGORY });

    test("neither entry point is shown, even for an admin in the allowed group", async function (assert) {
      await visit("/");
      assert.dom(SIDEBAR_LINK).doesNotExist();

      await visit("/t/grand-prix/9002");
      await click(".toggle-admin-menu");
      assert.dom(".event-duplicator-duplicate-topic").doesNotExist();
    });
  }
);

acceptance(
  "Event Duplicator - entry points (not in an allowed group)",
  function (needs) {
    needs.user({
      can_create_discourse_post_event: true,
      groups: [{ id: 14, name: "some-other-group" }],
    });
    needs.settings({
      event_duplicator_enabled: true,
      event_duplicator_allowed_groups: "3",
    });
    needs.site({ categories: [ALLOWED_CATEGORY] });
    withTopicPage(needs, { id: 9003, category: ALLOWED_CATEGORY });

    test("neither entry point is shown", async function (assert) {
      await visit("/");
      assert.dom(SIDEBAR_LINK).doesNotExist();

      await visit("/t/grand-prix/9003");
      await click(".toggle-admin-menu");
      assert.dom(".event-duplicator-duplicate-topic").doesNotExist();
    });
  }
);

acceptance(
  "Event Duplicator - entry points (discourse-calendar disallows the user)",
  function (needs) {
    needs.user({
      can_create_discourse_post_event: false,
      groups: [{ id: 3, name: "staff" }],
    });
    needs.settings({
      event_duplicator_enabled: true,
      event_duplicator_allowed_groups: "3",
    });
    needs.site({ categories: [ALLOWED_CATEGORY] });

    test("sidebar link is not shown", async function (assert) {
      await visit("/");
      assert.dom(SIDEBAR_LINK).doesNotExist();
    });
  }
);

acceptance(
  "Event Duplicator - entry points (category permission insufficient)",
  function (needs) {
    needs.user({
      can_create_discourse_post_event: true,
      groups: [{ id: 3, name: "staff" }],
    });
    needs.settings({
      event_duplicator_enabled: true,
      event_duplicator_allowed_groups: "3",
    });
    needs.site({ categories: [READ_ONLY_CATEGORY] });
    withTopicPage(needs, { id: 9004, category: READ_ONLY_CATEGORY });

    test("topic-admin button is hidden on a topic in a category the user can't create topics in, even though the group check passes", async function (assert) {
      await visit("/t/grand-prix/9004");
      await click(".toggle-admin-menu");

      assert.dom(".event-duplicator-duplicate-topic").doesNotExist();
    });
  }
);

acceptance(
  "Event Duplicator - entry points (topic has no discourse-calendar event)",
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
    withTopicPage(needs, {
      id: 9005,
      category: ALLOWED_CATEGORY,
      hasEvent: false,
    });

    // Regression test for GitHub issue #10: clicking this button on an
    // event-less topic used to route to the review page, which then 404'd
    // from `#proposed_dates` since it requires `topic.first_post&.event`.
    test("topic-admin button is hidden, even though the group and category checks pass", async function (assert) {
      await visit("/t/grand-prix/9005");
      await click(".toggle-admin-menu");

      assert.dom(".event-duplicator-duplicate-topic").doesNotExist();
    });
  }
);

acceptance(
  "Event Duplicator - entry points (user lacks category-moderator status)",
  function (needs) {
    // Deliberately not staff/TL4 -- `needs.user()` merges onto a fixture
    // (session-fixtures.js) that otherwise defaults to admin/moderator true
    // and trust_level 4, which would make Discourse core's own
    // TopicAdminMenu#showAdminButton pass regardless of the `details` flags
    // below and mask the very gap this test exists to cover.
    needs.user({
      admin: false,
      moderator: false,
      trust_level: 1,
      can_create_discourse_post_event: true,
      groups: [{ id: 20, name: "race-organizers" }],
    });
    needs.settings({
      event_duplicator_enabled: true,
      event_duplicator_allowed_groups: "20",
    });
    needs.site({ categories: [ALLOWED_CATEGORY] });
    withTopicPage(needs, {
      id: 9006,
      category: ALLOWED_CATEGORY,
      moderationCapable: false,
    });

    // Regression coverage for GitHub issue #11: this plugin's own three
    // checks (category permission, event_duplicator_allowed_groups,
    // discourse-calendar's post-event permission) all pass here, but the
    // topic-admin wrench menu itself is a Discourse core component
    // (TopicAdminMenu) that additionally requires category-moderator status
    // (staff/TL4/category moderator group) before it renders at all --
    // independent of anything this plugin checks. Without it, there's no
    // wrench trigger to click at all, not just a missing button inside it.
    test("the wrench menu itself does not render, so the button never has anywhere to appear", async function (assert) {
      await visit("/t/grand-prix/9006");

      assert.dom(".toggle-admin-menu").doesNotExist();
    });
  }
);
