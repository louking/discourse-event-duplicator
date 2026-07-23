import Service from "@ember/service";
import { ajax } from "discourse/lib/ajax";

export default class EventDuplicatorService extends Service {
  // GET the deduped, tagged topics eligible for series duplication.
  taggedTopics(tagName) {
    return ajax(`/event-duplicator/tags/${tagName}/topics`);
  }

  // GET the proposed new date(s) for a single topic's event.
  proposedDates(topicId) {
    return ajax(`/event-duplicator/topics/${topicId}/proposed_dates`);
  }

  // POST the reviewed/edited set of items to actually duplicate.
  duplicate(items) {
    return ajax("/event-duplicator/duplicate", {
      type: "POST",
      data: { items },
    });
  }
}
