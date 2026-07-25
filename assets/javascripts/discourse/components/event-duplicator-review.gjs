import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

// Dates are edited at day granularity only -- the original event's
// time-of-day is preserved and carried through untouched; only the
// calendar date portion is user-editable here. The end date isn't edited
// here at all -- TopicDuplicator derives it on the backend from the
// source event's own duration, so it can't drift out of sync with an
// edited start date.
function dateOnly(iso) {
  return iso ? iso.slice(0, 10) : "";
}

function withNewDate(newDate, previousIso) {
  if (!newDate) {
    return null;
  }
  const time = previousIso ? previousIso.slice(10) : "T00:00:00.000Z";
  return `${newDate}${time}`;
}

// A plain <input> without an explicit `size` renders at a fixed ~20-character
// default width regardless of its value, which clips a typical event title.
// Deriving `size` from the title's own length (each row independently, since
// this is per-item, not a single shared column width) lets the table's
// default auto layout size the whole Topic column to fit the longest title
// actually present, rather than every row having to fit inside a fixed guess.
const MIN_TITLE_INPUT_SIZE = 20;

function titleInputSize(title) {
  return Math.max(MIN_TITLE_INPUT_SIZE, (title ?? "").length + 2);
}

// The review/edit step: lists each proposed duplicate's original ("old")
// start date alongside the proposed ("new") start date, editable at day
// granularity, a "date TBD" flag (race events often don't have a settled
// date yet -- see TopicDuplicator#annotate on the backend), and a
// checkbox to include/exclude it, then confirms. Topics already
// duplicated to the same target occurrence (see DuplicationTracker on the
// backend) arrive with `selected: false` and are flagged in the table.
//
// Per-topic state is split into two parts: `@topics` (the proposal, which
// changes identity whenever the reviewer picks a different date rule --
// see the route's `date_strategy` query param) and `edits` (only the
// fields the user has actually touched, keyed by topic id, which survive
// a `@topics` change). This is deliberate: a plain `@tracked` field
// seeded from `@topics` at construction time would only ever reflect the
// *first* set of proposed dates, since Glimmer class field initializers
// run once and don't rerun when args change -- that was the bug behind
// changing the date rule appearing to have no effect. `edits` is a plain
// (non-tracked) Map; `revision` is bumped after every mutation so the
// `items` getter -- which reads `revision` -- knows to recompute.
export default class EventDuplicatorReview extends Component {
  @tracked revision = 0;

  edits = new Map();

  <template>
    <table class="event-duplicator-review">
      <thead>
        <tr>
          <th>
            <input
              type="checkbox"
              checked={{this.allSelected}}
              {{on "change" this.toggleAllSelected}}
            />
          </th>
          <th>{{i18n "event_duplicator.review.topic"}}</th>
          <th>{{i18n "event_duplicator.review.old_start"}}</th>
          <th>{{i18n "event_duplicator.review.new_start"}}</th>
          <th>
            <input
              type="checkbox"
              checked={{this.allTbd}}
              {{on "change" this.toggleAllTbd}}
            />
            {{i18n "event_duplicator.review.tbd"}}
          </th>
        </tr>
      </thead>
      <tbody>
        {{#each this.items key="topic.id" as |item|}}
          <tr>
            <td>
              <input
                type="checkbox"
                checked={{item.isSelected}}
                {{on "change" (fn this.toggleSelected item.topic.id)}}
              />
            </td>
            <td>
              <input
                type="text"
                class="event-duplicator-title"
                value={{item.title}}
                size={{item.titleSize}}
                {{on "change" (fn this.setTitle item.topic.id)}}
              />
              {{#if item.topic.already_duplicated}}
                <span class="event-duplicator-already-duplicated">
                  {{i18n
                    "event_duplicator.review.already_duplicated"
                    topic_id=item.topic.existing_duplicate_topic_id
                  }}
                </span>
              {{/if}}
            </td>
            <td>{{item.originalStartDate}}</td>
            <td>
              <input
                type="date"
                value={{item.startsAtDate}}
                {{on "change" (fn this.setStartsAt item.topic.id)}}
              />
            </td>
            <td>
              <input
                type="checkbox"
                checked={{item.tbd}}
                {{on "change" (fn this.toggleTbd item.topic.id)}}
              />
            </td>
          </tr>
        {{else}}
          <tr>
            <td colspan="5">{{i18n "event_duplicator.review.no_topics"}}</td>
          </tr>
        {{/each}}
      </tbody>
    </table>

    <DButton
      @class="btn-primary"
      @action={{this.confirm}}
      @disabled={{@isDuplicating}}
      @label="event_duplicator.review.confirm"
    />
  </template>

  // Returns a fresh array of fresh objects on every call (by design -- see
  // the class comment), so the template's `{{#each}}` is explicitly keyed
  // by `topic.id` rather than relying on Glimmer's default object-identity
  // key. Without that, every mutation (a single checkbox click, a date
  // edit) would make Glimmer treat every row as brand new and tear down
  // and recreate the whole `<tr>`, losing focus/scroll position.
  get items() {
    // eslint-disable-next-line no-unused-expressions
    this.revision;

    return (this.args.topics ?? []).map((topic) => {
      const edit = this.edits.get(topic.id) ?? {};
      const isSelected = edit.isSelected ?? topic.selected ?? true;
      // Duplicated dates are proposals, not confirmed race dates, so
      // default to flagging them as not-yet-settled.
      const tbd = edit.tbd ?? true;
      const startsAt = edit.startsAt ?? topic.proposed_start;
      const title = edit.title ?? topic.title;

      return {
        topic,
        isSelected,
        tbd,
        startsAt,
        title,
        titleSize: titleInputSize(title),
        originalStartDate: dateOnly(topic.original_start),
        startsAtDate: dateOnly(startsAt),
      };
    });
  }

  get allSelected() {
    return this.items.length > 0 && this.items.every((item) => item.isSelected);
  }

  get allTbd() {
    return this.items.length > 0 && this.items.every((item) => item.tbd);
  }

  setEdit(topicId, patch) {
    this.edits.set(topicId, { ...this.edits.get(topicId), ...patch });
    this.revision++;
  }

  @action
  toggleSelected(topicId) {
    const item = this.items.find((i) => i.topic.id === topicId);
    this.setEdit(topicId, { isSelected: !item.isSelected });
  }

  @action
  toggleAllSelected(event) {
    const checked = event.target.checked;
    for (const item of this.items) {
      this.edits.set(item.topic.id, {
        ...this.edits.get(item.topic.id),
        isSelected: checked,
      });
    }
    this.revision++;
  }

  @action
  toggleTbd(topicId) {
    const item = this.items.find((i) => i.topic.id === topicId);
    this.setEdit(topicId, { tbd: !item.tbd });
  }

  @action
  toggleAllTbd(event) {
    const checked = event.target.checked;
    for (const item of this.items) {
      this.edits.set(item.topic.id, {
        ...this.edits.get(item.topic.id),
        tbd: checked,
      });
    }
    this.revision++;
  }

  @action
  setStartsAt(topicId, event) {
    const item = this.items.find((i) => i.topic.id === topicId);
    this.setEdit(topicId, {
      startsAt: withNewDate(event.target.value, item.startsAt),
    });
  }

  @action
  setTitle(topicId, event) {
    this.setEdit(topicId, { title: event.target.value });
  }

  @action
  confirm() {
    const selectedItems = this.items
      .filter((item) => item.isSelected)
      .map((item) => ({
        topic: item.topic,
        startsAt: item.startsAt,
        tbd: item.tbd,
        title: item.title,
      }));

    this.args.onConfirm?.(selectedItems);
  }
}
