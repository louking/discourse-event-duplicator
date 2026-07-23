# frozen_string_literal: true

# name: discourse-event-duplicator
# about: Duplicate calendar events/topics into a new time period, individually or as a tagged series
# meta_topic_id: TODO
# version: 0.0.1
# authors: TODO
# url: https://github.com/TODO/discourse-event-duplicator
# required_version: 2.7.0

enabled_site_setting :event_duplicator_enabled

register_asset "stylesheets/common/event-duplicator.scss"

module ::DiscourseEventDuplicator
  PLUGIN_NAME = "discourse-event-duplicator"
end

require_relative "lib/discourse_event_duplicator/engine"

after_initialize do
  # discourse-calendar owns the topic/post custom fields (event start/end dates)
  # that this plugin reads and writes when duplicating events, so it must be
  # present and enabled.
  unless Discourse.plugins.any? { |plugin| plugin.name == "discourse-calendar" }
    Rails.logger.warn(
      "[#{DiscourseEventDuplicator::PLUGIN_NAME}] The discourse-calendar plugin is required but was not found. " \
        "Event duplication will not function correctly without it.",
    )
  end
end
