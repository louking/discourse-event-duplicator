# frozen_string_literal: true

DiscourseEventDuplicator::Engine.routes.draw do
  get "/tags/:tag_name/topics" => "event_duplicator#tagged_topics"
  get "/topics/:topic_id/proposed_dates" => "event_duplicator#proposed_dates"
  post "/duplicate" => "event_duplicator#duplicate"
end

Discourse::Application.routes.append { mount ::DiscourseEventDuplicator::Engine, at: "/event-duplicator" }
