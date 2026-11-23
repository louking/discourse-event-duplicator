# frozen_string_literal: true

# Loaded automatically by Discourse core's spec/rails_helper.rb.
module EventDuplicatorSpecHelpers
  # Turns on discourse-calendar's `enabled_site_setting`. Discourse core
  # renamed that plugin to discourse-events in Aug 2026, and its
  # `calendar_enabled` setting to `discourse_events_enabled`; set whichever
  # this Discourse version has so the specs run on both.
  def enable_events_plugin!
    if SiteSetting.respond_to?(:discourse_events_enabled=)
      SiteSetting.discourse_events_enabled = true
    else
      SiteSetting.calendar_enabled = true
    end
  end

  # Writes an `[event ...]` tag matching `event` into its post's raw.
  # Fabricating an event row doesn't touch the post, and TopicDuplicator
  # copies the source post's raw, so it needs a real tag to rewrite.
  # update_column skips discourse-calendar's post validation and event sync.
  def write_event_tag!(event, body: nil)
    attrs = {
      "start" =>
        event.original_starts_at.in_time_zone(event.timezone || "UTC").strftime("%Y-%m-%d %H:%M"),
      "end" =>
        event.original_ends_at&.in_time_zone(event.timezone || "UTC")&.strftime("%Y-%m-%d %H:%M"),
      "name" => event.name,
      "timezone" => event.timezone,
    }
    tag = attrs.filter_map { |key, value| %(#{key}="#{value}") if value.present? }.join(" ")
    event.post.update_column(:raw, ["[event #{tag}]\n[/event]", body].compact.join("\n\n"))
    event
  end
end

RSpec.configure { |config| config.include EventDuplicatorSpecHelpers }
