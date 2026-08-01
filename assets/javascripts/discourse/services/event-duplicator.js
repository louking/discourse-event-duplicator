import Service from "@ember/service";
import { ajax } from "discourse/lib/ajax";

export default class EventDuplicatorService extends Service {
  // GET the deduped topics eligible for series duplication: matches any of
  // `tags` (OR), scoped to `categoryId`, optionally restricted to events
  // starting within `startsAfter`/`startsBefore`.
  taggedTopics({
    categoryId,
    tags = [],
    startsAfter,
    startsBefore,
    dateStrategy,
    shiftMonths,
  } = {}) {
    const [tagName, ...additionalTags] = tags;

    return ajax(`/event-duplicator/tags/${tagName}/topics`, {
      data: {
        category_id: categoryId,
        additional_tags: additionalTags,
        starts_after: startsAfter,
        starts_before: startsBefore,
        date_strategy: dateStrategy,
        shift_months: shiftMonths,
      },
    });
  }

  // GET the proposed new date(s) for a single topic's event.
  proposedDates(topicId, dateStrategy, shiftMonths) {
    return ajax(`/event-duplicator/topics/${topicId}/proposed_dates`, {
      data: { date_strategy: dateStrategy, shift_months: shiftMonths },
    });
  }

  // POST the reviewed/edited set of items to actually duplicate. Each item
  // is `{ topic_id, starts_at, tbd, force }` -- no `ends_at`; the backend
  // derives the end date from the source event's own duration.
  //
  // Sent as an explicit JSON body (`contentType` + a pre-stringified
  // `data`), not `data: { items }` as-is -- without that, `ajax()` (a thin
  // wrapper over `$.ajax`) falls back to jQuery's default
  // application/x-www-form-urlencoded encoding, which serializes an array
  // of objects as indexed bracket params (`items[0][topic_id]=...`). Rails
  // parses that into a Hash keyed by the string "0", not an Array, so the
  // controller's `Array(params[:items])` wraps the *whole* hash as a single
  // bogus item instead of decomposing it -- `topic_id` reads back as `nil`
  // and every duplication 404s (confirmed live: request specs never catch
  // this, since they post `items:` as a real Ruby array through Rails' own
  // test helpers, sidestepping jQuery's serialization entirely). Matches
  // the pattern Discourse core itself uses for array/object payloads, e.g.
  // `Topic.update`/`Topic.bulkOperation` in `discourse/models/topic.js`.
  duplicate(items) {
    return ajax("/event-duplicator/duplicate", {
      type: "POST",
      contentType: "application/json",
      data: JSON.stringify({ items }),
    });
  }
}
