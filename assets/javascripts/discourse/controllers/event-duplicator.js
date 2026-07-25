import Controller from "@ember/controller";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import Category from "discourse/models/category";

export default class EventDuplicatorController extends Controller {
  @service eventDuplicator;
  @service router;
  @service composer;
  @service appEvents;

  @tracked isDuplicating = false;

  queryParams = [
    "topic_id",
    "category_id",
    "tags",
    "starts_after",
    "starts_before",
    "date_strategy",
  ];

  get tagsLabel() {
    return (this.model?.tags ?? []).join(", ");
  }

  // Series duplication (no topic_id) creates every selected topic directly
  // on confirm. Single-topic duplication (from the topic-admin menu) opens
  // the real Discourse composer instead, pre-filled, so the reviewer
  // finishes and posts it themselves -- see #openInComposer.
  get confirmLabel() {
    return this.topic_id
      ? "event_duplicator.review.open_in_composer"
      : "event_duplicator.review.confirm";
  }

  @action
  setDateStrategy(event) {
    this.router.transitionTo("event-duplicator", {
      queryParams: { date_strategy: event.target.value },
    });
  }

  @action
  async confirmDuplication(selectedItems) {
    if (this.topic_id) {
      return this.openInComposer(selectedItems[0]);
    }

    return this.duplicateSelected(selectedItems);
  }

  async duplicateSelected(selectedItems) {
    this.isDuplicating = true;

    // `already_duplicated` topics default to unselected (see
    // DuplicatableTopicSerializer#selected) specifically so a second series
    // run doesn't silently re-create something -- so a reviewer explicitly
    // re-checking one of those rows *is* the deliberate override the
    // backend's `force` param exists for. Without sending it, checking the
    // box back on would look like it worked (item stays in the request)
    // but the backend would still silently skip it into `skipped`.
    const items = selectedItems.map((item) => ({
      topic_id: item.topic.id,
      starts_at: item.startsAt,
      tbd: item.tbd,
      title: item.title,
      force: item.topic.already_duplicated,
    }));

    try {
      await this.eventDuplicator.duplicate(items);
    } finally {
      this.isDuplicating = false;
    }
  }

  // Fetches the title/raw body/category/tags a duplicate would have at the
  // reviewer's edited date/title/TBD flag (without creating anything --
  // see TopicDuplicator#preview), then opens the real Discourse composer
  // pre-filled with them. Nothing is created until the reviewer finishes
  // and posts it themselves through the composer's normal save path, which
  // means normal Discourse validations (e.g. duplicate-title) apply here,
  // unlike the direct-create path in #duplicateSelected.
  async openInComposer(item) {
    if (!item) {
      return;
    }

    const sourceTopicId = item.topic.id;

    this.isDuplicating = true;
    let prefill;
    try {
      prefill = await this.eventDuplicator.composerPrefill(sourceTopicId, {
        startsAt: item.startsAt,
        tbd: item.tbd,
        title: item.title,
      });
    } finally {
      this.isDuplicating = false;
    }

    await this.composer.openNewTopic({
      title: prefill.title,
      body: prefill.raw,
      category: Category.findById(prefill.category_id),
      // `openNewTopic`/`filterTags` expects a comma-separated string here,
      // not an array -- passing the array through as-is works for staff
      // (the common case, since event_duplicator_allowed_groups defaults
      // to staff-only) but breaks for a non-staff allowed group, where
      // `filterTags` calls `.content` on it expecting an Ember array.
      tags: (prefill.tags ?? []).join(","),
    });

    // The composer creates the topic itself through Discourse's normal
    // save path (not TopicDuplicator), so DuplicationTracker doesn't hear
    // about it unless we report it back once that succeeds. `topic:created`
    // is a global event, so it's guarded by comparing against the exact
    // composer model instance this session just opened -- otherwise an
    // unrelated topic created elsewhere while this one sits abandoned
    // would be misattributed as this duplicate.
    const composerModel = this.composer.model;

    const cleanup = () => {
      this.appEvents.off("topic:created", handleCreated);
      this.appEvents.off("composer:cancelled", handleCancelled);
    };

    const handleCreated = async (post, composerOfPost) => {
      if (composerOfPost !== composerModel) {
        return;
      }
      cleanup();
      await this.eventDuplicator.recordDuplicate(sourceTopicId, post.topic_id);
    };

    const handleCancelled = () => cleanup();

    this.appEvents.on("topic:created", handleCreated);
    this.appEvents.on("composer:cancelled", handleCancelled);
  }
}
