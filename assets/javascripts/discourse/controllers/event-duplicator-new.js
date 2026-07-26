import Controller from "@ember/controller";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { tracked } from "@glimmer/tracking";

export default class EventDuplicatorNewController extends Controller {
  @service router;

  @tracked categoryId = null;
  @tracked tags = [];
  @tracked startsAfter = null;
  @tracked startsBefore = null;

  get canProceed() {
    return !!this.categoryId && this.tags.length > 0;
  }

  @action
  setCategoryId(categoryId) {
    this.categoryId = categoryId;
  }

  @action
  setTags(tags) {
    // TagChooser's onChange hands back full tag objects ({id, name, ...}),
    // not plain name strings -- normalize defensively either way.
    this.tags = (tags ?? []).map((tag) =>
      typeof tag === "string" ? tag : tag.name
    );
  }

  // Plain native date inputs (rather than Ember's <Input> component) so
  // clearing the field reliably reaches us as an empty string -> null,
  // leaving that end of the range open (unbounded).
  @action
  setStartsAfter(event) {
    this.startsAfter = event.target.value || null;
  }

  @action
  setStartsBefore(event) {
    this.startsBefore = event.target.value || null;
  }

  // Explicit clear actions, rather than relying on the reviewer to clear a
  // native date input by hand -- Chrome's segmented mm/dd/yyyy editing only
  // clears whichever segment currently has focus (not the whole field) when
  // backspacing, so a user backspacing through the field is often left with
  // stale digits still visible in the other segments even though `.value`
  // itself has already gone empty. Setting the tracked property directly
  // (as these actions do) re-binds the input's `value` property as a whole,
  // which does reset every segment back to the mm/dd/yyyy placeholder.
  @action
  clearStartsAfter() {
    this.startsAfter = null;
  }

  @action
  clearStartsBefore() {
    this.startsBefore = null;
  }

  @action
  proceed() {
    this.router.transitionTo("event-duplicator", {
      queryParams: {
        // `transitionTo`'s queryParams merges with whatever's already
        // active rather than replacing it wholesale -- without explicitly
        // nulling `topic_id` here, a `topic_id` left over from an earlier
        // single-topic duplication (topic-admin menu button) stays in the
        // URL, and the review route's `model()` checks `params.topic_id`
        // first, so it silently stays in single-topic mode showing that
        // stale topic instead of the series you just picked.
        topic_id: null,
        category_id: this.categoryId,
        tags: this.tags.join(","),
        starts_after: this.startsAfter || null,
        starts_before: this.startsBefore || null,
      },
    });
  }
}
