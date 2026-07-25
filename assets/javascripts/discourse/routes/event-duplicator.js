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
  };

  async model(params) {
    const dateStrategy =
      params.date_strategy ||
      this.siteSettings.event_duplicator_default_date_strategy;

    if (params.topic_id) {
      return this.modelForSingleTopic(params, dateStrategy);
    }

    return this.modelForTaggedSeries(params, dateStrategy);
  }

  async modelForSingleTopic(params, dateStrategy) {
    const proposed = await this.eventDuplicator.proposedDates(
      params.topic_id,
      dateStrategy
    );

    return {
      tags: [],
      dateStrategy,
      topics: [
        {
          id: proposed.topic_id,
          title: proposed.title,
          original_start: proposed.original_start,
          original_end: proposed.original_end,
          proposed_start: proposed.proposed_start,
          proposed_end: proposed.proposed_end,
          already_duplicated: false,
          selected: true,
        },
      ],
    };
  }

  async modelForTaggedSeries(params, dateStrategy) {
    const tags = (params.tags || "").split(",").filter(Boolean);
    const { topics } = await this.eventDuplicator.taggedTopics({
      categoryId: params.category_id,
      tags,
      startsAfter: params.starts_after,
      startsBefore: params.starts_before,
      dateStrategy,
    });

    return { tags, dateStrategy, topics };
  }
}
