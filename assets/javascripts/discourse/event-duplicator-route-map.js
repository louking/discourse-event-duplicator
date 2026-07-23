export default function () {
  // Placeholder top-level route. Real entry point (a button on tag pages
  // and/or a topic-admin menu item, gated on the same category permission
  // the backend checks) is still TBD.
  this.route("event-duplicator", { path: "/event-duplicator/:tag_name" });
}
