# frozen_string_literal: true

# Mounted at "/" (not at "/event-duplicator") with each route fully-qualified
# below, rather than mounting the whole engine at the "/event-duplicator"
# prefix -- the Ember UI also lives under that same prefix
# (/event-duplicator/new, /event-duplicator/review), and a prefix-mounted
# engine swallows every sub-path, so a full page load/refresh on those Ember
# routes would hit this engine's router, find no matching action, and 404
# instead of falling through to Discourse's SPA shell. Matches the pattern
# discourse-calendar uses for the same reason (see its config/routes.rb).
DiscourseEventDuplicator::Engine.routes.draw do
  get "/event-duplicator/tags/:tag_name/topics" => "event_duplicator#tagged_topics"
  get "/event-duplicator/topics/:topic_id/proposed_dates" => "event_duplicator#proposed_dates"
  get "/event-duplicator/topics/:topic_id/composer_prefill" => "event_duplicator#composer_prefill"
  post "/event-duplicator/topics/:topic_id/record_duplicate" => "event_duplicator#record_duplicate"
  post "/event-duplicator/duplicate" => "event_duplicator#duplicate"

  # Serve the SPA shell for the Ember-only pages (see PagesController).
  get "/event-duplicator/new" => "pages#new"
  get "/event-duplicator/review" => "pages#review"
end

Discourse::Application.routes.draw { mount ::DiscourseEventDuplicator::Engine, at: "/" }
