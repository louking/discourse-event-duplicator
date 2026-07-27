import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";
import { canDuplicateEvents } from "../lib/can-duplicate-events";

export default apiInitializer((api) => {
  const currentUser = api.getCurrentUser();
  const siteSettings = api.container.lookup("service:site-settings");

  // Series duplication: a sidebar link to the category+tags picker. This is
  // the sole entry point for series duplication -- it isn't tied to already
  // being on a specific tag or category page, which matters since a run can
  // span multiple tags (OR).
  api.addCommunitySectionLink((baseSectionLink) => {
    return class EventDuplicatorSectionLink extends baseSectionLink {
      get name() {
        return "event-duplicator";
      }

      get route() {
        return "event-duplicator-new";
      }

      get title() {
        return i18n("event_duplicator.sidebar.link_title");
      }

      get text() {
        return i18n("event_duplicator.sidebar.link_text");
      }

      get defaultPrefixValue() {
        return "copy";
      }

      get shouldDisplay() {
        return canDuplicateEvents(this.currentUser, this.siteSettings);
      }
    };
  });

  // Single-topic duplication: a topic-admin menu button, gated on the same
  // combined check the backend enforces (group membership here, category
  // permission via `canCreateTopic`) plus the topic actually having a
  // discourse-calendar event -- without that last check, the button would
  // render on any topic and clicking it would 404 on the review page (the
  // backend requires `topic.first_post&.event`; see GitHub issue #10). This
  // relies on `event_duplicator_has_event`, added onto the topic_view
  // serializer in this plugin's own `plugin.rb`.
  api.addTopicAdminMenuButton((topic) => {
    if (!canDuplicateEvents(currentUser, siteSettings)) {
      return null;
    }

    if (!topic.category?.canCreateTopic) {
      return null;
    }

    if (!topic.event_duplicator_has_event) {
      return null;
    }

    return {
      action: () => {
        const router = api.container.lookup("service:router");
        router.transitionTo("event-duplicator", {
          // See the matching comment in controllers/event-duplicator-new.js
          // -- `transitionTo`'s queryParams merges rather than replaces, so
          // series-mode params left over from a previous visit need
          // clearing explicitly too, even though `model()` already
          // prioritizes `topic_id` and so wouldn't visibly misbehave here.
          // `date_strategy` belongs in this list too, unlike the others:
          // `model()` doesn't prioritize it away, so a rule picked during an
          // earlier series-mode visit (e.g. "Same weekday of month") silently
          // carried over and was used to compute this topic's proposed date
          // instead of the intended default -- see GitHub issue #13.
          queryParams: {
            topic_id: topic.id,
            category_id: null,
            tags: null,
            starts_after: null,
            starts_before: null,
            date_strategy: null,
          },
        });
      },
      icon: "copy",
      className: "event-duplicator-duplicate-topic",
      label: "event_duplicator.topic_admin_menu.duplicate",
    };
  });
});
