# frozen_string_literal: true

module ::DiscourseEventDuplicator
  # Creates a duplicate of a calendar-event topic at the given (already
  # reviewed/confirmed) dates. Duplication works by creating a new topic
  # whose first post contains an `[event ...]` raw block built from the
  # source event's other attributes -- discourse-calendar's own
  # `on(:post_created)` hook then parses that block and creates the `Event`
  # row for us, so its validations, invitee handling, and topic-custom-field
  # sync all apply exactly as they would for a hand-authored event post.
  class TopicDuplicator
    def initialize(source_topic:, actor:, starts_at:, tbd: false)
      @source_topic = source_topic
      @actor = actor
      @starts_at = starts_at
      @tbd = tbd
    end

    def call
      post =
        PostCreator.create!(
          @actor,
          title: annotate(@source_topic.title),
          raw: event_raw,
          category: @source_topic.category_id,
          tags: @source_topic.tags.map(&:name),
          archetype: Archetype.default,
          # A duplicate is expected to reuse the source topic's title, which
          # would otherwise trip Discourse's default "no duplicate titles"
          # validation -- that and the other generic topic/post content
          # checks are redundant here since this is a copy of already-valid,
          # code-generated content, not fresh user input. This does *not*
          # skip discourse-calendar's own event validation (acting-user
          # permission, date sanity, etc.), which is registered as an
          # independent Post validation and still runs.
          skip_validations: true,
        )
      post.topic
    end

    private

    def source_event
      @source_event ||= @source_topic.first_post&.event
    end

    # The reviewer only edits the start date -- the end date is derived by
    # carrying over the source event's own duration rather than being
    # independently editable, so it can't drift out of sync with a manually
    # adjusted start.
    def effective_ends_at
      return nil unless source_event&.starts_at && source_event.ends_at

      @starts_at + (source_event.ends_at - source_event.starts_at)
    end

    # Race events often don't have a settled date yet; marking a duplicate
    # as such appends (or, if unmarked, strips a stale) annotation to the
    # title and event name, rather than leaving no way to flag it.
    def annotate(text)
      annotation = SiteSetting.event_duplicator_tbd_annotation
      return text if annotation.blank?

      base = text.delete_suffix(annotation)
      @tbd ? "#{base}#{annotation}" : base
    end

    def event_raw
      event = source_event
      timezone = event&.timezone || "UTC"
      all_day = event&.all_day || false

      ends_at = effective_ends_at

      attrs = {
        "start" => format_time(@starts_at, timezone, all_day),
        "end" => ends_at && format_time(ends_at, timezone, all_day),
        "name" => event&.name && annotate(event.name),
        "timezone" => event&.timezone,
        "status" => event && DiscoursePostEvent::Event.statuses[event.status].to_s,
        "recurrence" => event&.recurrence,
        "recurrence-until" =>
          event&.recurrence_until && format_time(event.recurrence_until, timezone, false),
        "all-day" => all_day ? "true" : nil,
      }

      parts = attrs.filter_map { |key, value| %(#{key}="#{value}") if value.present? }
      "[event #{parts.join(" ")}]\n[/event]"
    end

    def format_time(time, timezone, all_day)
      zoned = time.in_time_zone(timezone)
      all_day ? zoned.strftime("%Y-%m-%d") : zoned.strftime("%Y-%m-%d %H:%M")
    end
  end
end
