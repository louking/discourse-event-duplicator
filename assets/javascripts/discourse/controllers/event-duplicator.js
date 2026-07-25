import Controller from "@ember/controller";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";

export default class EventDuplicatorController extends Controller {
  @service eventDuplicator;
  @service router;

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

  @action
  setDateStrategy(event) {
    this.router.transitionTo("event-duplicator", {
      queryParams: { date_strategy: event.target.value },
    });
  }

  @action
  async confirmDuplication(selectedItems) {
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
}
