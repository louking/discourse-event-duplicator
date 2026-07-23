import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";

// Placeholder for the review/edit step: lists each proposed duplicate with
// its editable date(s) and a checkbox to include/exclude it, then confirms.
export default class EventDuplicatorReview extends Component {
  @tracked selections = new Map(
    (this.args.topics ?? []).map((topic) => [topic.id, true])
  );

  get items() {
    return (this.args.topics ?? []).map((topic) => ({
      topic,
      isSelected: this.selections.get(topic.id) ?? true,
    }));
  }

  @action
  toggle(topicId) {
    this.selections.set(topicId, !this.selections.get(topicId));
    // eslint-disable-next-line no-self-assign
    this.selections = this.selections;
  }

  @action
  confirm() {
    const selectedItems = this.items
      .filter((item) => item.isSelected)
      .map((item) => item.topic);

    this.args.onConfirm?.(selectedItems);
  }
}
