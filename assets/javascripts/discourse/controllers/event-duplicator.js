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

  // The Date rule <select>'s selected option is driven by these rather than
  // a `value={{this.model.dateStrategy}}` binding on the <select> itself --
  // that was tried first and is the actual cause of GitHub issue #13
  // ("review form" showing the wrong date while the dropdown looked right).
  // Glimmer sets `value` on a <select> as a DOM property (confirmed against
  // its `normalizeProperty`: "value" is an own property of a select
  // element, so it isn't forced to plain-attribute), but it does so when the
  // <select>'s opening tag is flushed, before its <option> children exist in
  // the DOM yet -- so the assignment has no effect once those options are
  // appended, and the browser silently falls back to selecting the first
  // <option> ("Same calendar date") regardless of the real active strategy.
  // Setting `selected` directly on each <option> sidesteps the ordering
  // problem entirely, since HTMLOptionElement#selected only marks that
  // option's own internal selectedness flag and doesn't depend on the
  // <select> parent existing yet.
  get isCalendarDateStrategy() {
    return this.model?.dateStrategy === "calendar_date";
  }

  get isNthWeekdayOfMonthStrategy() {
    return this.model?.dateStrategy === "nth_weekday_of_month";
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
    // Not reset to null here (only replaced once the new response lands) --
    // see the `duplicated` accumulation note below; nulling it out early
    // would flash previously-duplicated rows back to their enabled state
    // for the duration of this request.
    const previouslyDuplicated = this.result?.duplicated ?? [];

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
      // `duplicated` accumulates across submissions (rather than being
      // replaced) because the review table marks a row's checkbox disabled
      // and excludes it from the next submission once it's in this list
      // (see EventDuplicatorReview#confirm's `justDuplicated` guard) -- a
      // reviewer retrying a partially-failed batch would otherwise lose the
      // "duplicated to topic" link/disabled state on rows that already
      // succeeded in an earlier submission. `skipped` reflects only the
      // latest attempt, since a retry's skip reasons supersede stale ones.
      this.result = {
        duplicated: [
          ...previouslyDuplicated,
          ...response.duplicated.map((entry) => ({
            ...entry,
            title: titlesByTopicId.get(entry.topic_id),
          })),
        ],
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
