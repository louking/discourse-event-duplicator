import Route from "@ember/routing/route";
import { service } from "@ember/service";

export default class EventDuplicatorRoute extends Route {
  @service eventDuplicator;

  async model(params) {
    const { topics } = await this.eventDuplicator.taggedTopics(params.tag_name);

    return { tagName: params.tag_name, topics };
  }
}
