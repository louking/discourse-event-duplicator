export default function () {
  // Picker: choose a category + one or more series tags (OR) + optional
  // source-event date range, then proceed to the review route below.
  this.route("event-duplicator-new", { path: "/event-duplicator/new" });

  // Review/edit step: either a tagged series (category_id + tags[]) or a
  // single topic (topic_id), loaded via query params rather than a dynamic
  // segment so both entry points can share one route.
  this.route("event-duplicator", { path: "/event-duplicator/review" });
}
