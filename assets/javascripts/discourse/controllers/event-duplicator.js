import Controller from "@ember/controller";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";

export default class EventDuplicatorController extends Controller {
  @service eventDuplicator;
  @service router;

  @tracked isDuplicating = false;
  @tracked result = null;

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
    this.result = null;

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

    // The backend response's `duplicated`/`skipped` entries only carry
    // `topic_id`, not a title -- keep a local lookup (preferring the
    // reviewer's edited title, if any) so the result panel can show a
    // human-readable label rather than a bare id.
    const titlesByTopicId = new Map(
      selectedItems.map((item) => [item.topic.id, item.title])
    );

    try {
      const response = await this.eventDuplicator.duplicate(items);
      this.result = {
        duplicated: response.duplicated.map((entry) => ({
          ...entry,
          title: titlesByTopicId.get(entry.topic_id),
        })),
        skipped: response.skipped.map((entry) => ({
          ...entry,
          title: titlesByTopicId.get(entry.topic_id),
        })),
      };
    } finally {
      this.isDuplicating = false;
    }
  }
}
