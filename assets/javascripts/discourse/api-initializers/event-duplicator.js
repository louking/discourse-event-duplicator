import { apiInitializer } from "discourse/lib/plugin-api";

export default apiInitializer("1.8.0", () => {
  // TODO: wire up the real entry point once placement is decided — likely a
  // button on tag pages (api.decorateTagPage / addTagsHtmlCallback) and/or a
  // topic-admin menu item, both gated on the same
  // `guardian.can_create_topic_on_category?(category)` check the backend enforces so the
  // control simply doesn't render for users who couldn't use it anyway.
});
