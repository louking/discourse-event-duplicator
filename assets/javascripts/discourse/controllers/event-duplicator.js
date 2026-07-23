import Controller from "@ember/controller";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";

export default class EventDuplicatorController extends Controller {
  @service eventDuplicator;
  @service router;

  @tracked isDuplicating = false;

  @action
  async confirmDuplication(selectedItems) {
    this.isDuplicating = true;

    try {
      await this.eventDuplicator.duplicate(selectedItems);
    } finally {
      this.isDuplicating = false;
    }
  }
}
