# frozen_string_literal: true

# name: discourse-event-duplicator
# about: Duplicate calendar events/topics into a new time period, individually or as a tagged series
# meta_topic_id: TODO
# version: 1.1.0
# authors: Lou King
# url: https://github.com/louking/discourse-event-duplicator
# required_version: 2.7.0

enabled_site_setting :event_duplicator_enabled

register_asset "stylesheets/common/event-duplicator.scss"

module ::DiscourseEventDuplicator
  PLUGIN_NAME = "discourse-event-duplicator"
end

require_relative "lib/discourse_event_duplicator/engine"

after_initialize do
  # Lets the frontend hide the topic-admin "Duplicate event" button on
  # topics with no discourse-calendar event, instead of rendering it and
  # then 404ing on the review page once clicked (see GitHub issue #10).
  # discourse-calendar's own `event_starts_at` topic_view attribute isn't
  # suitable for this: it's gated behind the unrelated
  # `display_post_event_date_on_topic_title` site setting, so it can be
  # absent from the payload even when the topic does have an event.
  add_to_serializer(:topic_view, :event_duplicator_has_event) do
    object.topic.first_post&.event.present?
  end

  register_topic_custom_field_type(
    DiscourseEventDuplicator::DuplicationTracker::FIELD_NAME,
    :json,
  )
  register_topic_custom_field_type(
    DiscourseEventDuplicator::DuplicationTracker::SOURCE_FIELD_NAME,
    :json,
  )

  # Deleting a duplicate topic (this plugin's own creation) makes its source
  # topic eligible for re-duplication again, as if the duplicate had never
  # been created; recovering it re-locks that eligibility. :topic_trashed is
  # the common, reversible delete path; :topic_destroyed also covers a
  # direct permanent delete (which skips trash entirely) -- both call the
  # same idempotent DuplicationTracker#forget!, see its comments for why
  # that's safe. See DuplicationTracker for the reverse-pointer mechanism
  # this relies on.
  on(:topic_trashed) do |topic|
    DiscourseEventDuplicator::DuplicationTracker.forget!(duplicate_topic: topic)
  end

  on(:topic_destroyed) do |topic, _user|
    DiscourseEventDuplicator::DuplicationTracker.forget!(duplicate_topic: topic)
  end

  on(:topic_recovered) do |topic|
    DiscourseEventDuplicator::DuplicationTracker.restore!(duplicate_topic: topic)
  end

  # discourse-calendar owns event data via DiscoursePostEvent::Event
  # (original_starts_at/original_ends_at, populated by parsing an [event]
  # block out of a post's raw text), not via plugin-local custom fields --
  # this plugin must read/write through that, so it depends on
  # discourse-calendar being present.
  unless Discourse.plugins.any? { |plugin| plugin.name == "discourse-calendar" }
    Rails.logger.warn(
      "[#{DiscourseEventDuplicator::PLUGIN_NAME}] The discourse-calendar plugin is required but was not found. " \
        "Event duplication will not function correctly without it.",
    )
  end
end
