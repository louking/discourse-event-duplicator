import Route from "@ember/routing/route";
import { service } from "@ember/service";

export default class EventDuplicatorRoute extends Route {
  @service eventDuplicator;
  @service siteSettings;

  queryParams = {
    topic_id: { refreshModel: true },
    category_id: { refreshModel: true },
    tags: { refreshModel: true },
    starts_after: { refreshModel: true },
    starts_before: { refreshModel: true },
    date_strategy: { refreshModel: true },
    shift_months: { refreshModel: true },
  };

  async model(params) {
    const dateStrategy =
      params.date_strategy ||
      this.siteSettings.event_duplicator_default_date_strategy;
    const shiftMonths =
      parseInt(params.shift_months, 10) ||
      this.siteSettings.event_duplicator_default_shift_months;

    if (params.topic_id) {
      return this.modelForSingleTopic(params, dateStrategy, shiftMonths);
    }

    return this.modelForTaggedSeries(params, dateStrategy, shiftMonths);
  }

  // A fresh model fetch means `topics` now carries up-to-date
  // `already_duplicated`/`existing_duplicate_topic_url` straight from
  // DuplicationTracker -- the authoritative source. The controller's
  // `result` (the previous "duplicated to topic" confirmation state, see
  // `confirmDuplication`) is only meant to bridge the gap between
  // confirming a batch and the next time the model is actually refetched;
  // holding onto it past that point makes it actively wrong rather than
  // just stale. Concretely: duplicate a topic, delete that duplicate
  // (freeing the source back up via DuplicationTracker#forget!), then
  // revisit this route (or flip the date-rule dropdown, which
  // `refreshModel`s the same way) -- without this reset, `result.duplicated`
  // still names the deleted topic and the review row kept showing
  // "duplicated to topic" even though the fresh `already_duplicated: false`
  // said otherwise, since the controller is a singleton whose `result`
  // survives across route re-entries. See GitHub issue #16.
  setupController(controller, model) {
    super.setupController(controller, model);
    controller.result = null;
  }

  async modelForSingleTopic(params, dateStrategy, shiftMonths) {
    const proposed = await this.eventDuplicator.proposedDates(
      params.topic_id,
      dateStrategy,
      shiftMonths
    );

    return {
      tags: [],
      dateStrategy,
      shiftMonths,
      topics: [
        {
          id: proposed.topic_id,
          title: proposed.title,
          original_start: proposed.original_start,
          original_end: proposed.original_end,
          proposed_start: proposed.proposed_start,
          proposed_end: proposed.proposed_end,
          already_duplicated: proposed.already_duplicated,
          existing_duplicate_topic_id: proposed.existing_duplicate_topic_id,
          existing_duplicate_topic_url: proposed.existing_duplicate_topic_url,
          selected: !proposed.already_duplicated,
        },
      ],
    };
  }

  async modelForTaggedSeries(params, dateStrategy, shiftMonths) {
    const tags = (params.tags || "").split(",").filter(Boolean);
    const { topics } = await this.eventDuplicator.taggedTopics({
      categoryId: params.category_id,
      tags,
      startsAfter: params.starts_after,
      startsBefore: params.starts_before,
      dateStrategy,
      shiftMonths,
    });

    return { tags, dateStrategy, shiftMonths, topics };
  }
}
