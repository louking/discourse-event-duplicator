import Route from "@ember/routing/route";
import { service } from "@ember/service";
import { canDuplicateEvents } from "../lib/can-duplicate-events";

export default class EventDuplicatorNewRoute extends Route {
  @service currentUser;
  @service siteSettings;
  @service router;

  beforeModel() {
    // Defense in depth for direct URL navigation -- the sidebar link itself
    // already only renders for eligible users.
    if (!canDuplicateEvents(this.currentUser, this.siteSettings)) {
      this.router.transitionTo("discovery.latest");
    }
  }
}
