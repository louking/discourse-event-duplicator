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
end

RSpec.configure { |config| config.include EventDuplicatorSpecHelpers }
