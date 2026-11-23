# frozen_string_literal: true

module ::DiscourseEventDuplicator
  # Creates a duplicate of a calendar-event topic at the given (already
  # reviewed/confirmed) dates. Duplication works by creating a new topic
  # whose first post is a copy of the source topic's first post, with the
  # `[event ...]` tag's dates and name rewritten -- discourse-calendar's own
  # `on(:post_created)` hook then parses that block and creates the `Event`
  # row for us, so its validations, invitee handling, and topic-custom-field
  # sync all apply exactly as they would for a hand-authored event post.
  class TopicDuplicator
    # Matches the opening `[event ...]` tag in a post's raw, capturing its
    # attributes. Attribute values are double-quoted, as discourse-calendar's
    # own composer builder writes them.
    EVENT_TAG = /\[event((?:\s+[\w-]+="[^"]*")*)\s*\]/i
    EVENT_ATTR = /([\w-]+)="([^"]*)"/

    # Raised when the source post's raw has no `[event ...]` tag. Such a
    # topic isn't an event topic, so it isn't duplicated.
    class MissingEventTag < StandardError
      def initialize(msg = "source topic has no [event] block")
        super
      end
    end

    def initialize(source_topic:, actor:, starts_at:, tbd: false, title: nil)
      @source_topic = source_topic
      @actor = actor
      @starts_at = starts_at
      @tbd = tbd
      @title = title.presence
    end

    def call
      post =
        PostCreator.create!(
          @actor,
          title: annotate(effective_title),
          raw: duplicate_raw,
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

    # Reviewers can override the source topic's title (e.g. to drop a year
    # baked into the name) rather than always reusing it verbatim.
    def effective_title
      @title || @source_topic.title
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
    # title and event name, rather than leaving no way to flag it. The
    # separating space is inserted here rather than expected as part of the
    # site setting's own value: Discourse core's SiteSetting::Update service
    # unconditionally `.strip`s every setting value on save
    # (app/services/site_setting/update.rb), so a setting value entered as
    # e.g. " (TBD)" is persisted as "(TBD)" with the leading space silently
    # gone -- any leading/trailing whitespace baked into the setting itself
    # can't survive being saved through the admin UI. See GitHub issue #17.
    def annotate(text)
      annotation = SiteSetting.event_duplicator_tbd_annotation
      return text if annotation.blank?

      suffix = " #{annotation}"
      base = text.delete_suffix(suffix)
      @tbd ? "#{base}#{suffix}" : base
    end

    # The source post's raw with only the event tag rewritten, so the
    # topic's own text and any event attributes this class doesn't know
    # about (location, url, reminders, custom fields, ...) carry over. See
    # GitHub issue #21.
    def duplicate_raw
      raw = @source_topic.first_post&.raw.to_s
      match = raw.match(EVENT_TAG)
      raise MissingEventTag if match.nil?

      attrs = match[1].scan(EVENT_ATTR).to_h
      attrs.merge!(date_attrs)
      # A title override should carry through to the event's own name too,
      # so the calendar widget doesn't keep showing the old name once the
      # topic title has been changed.
      if attrs["name"].present? || source_event&.name.present?
        attrs["name"] = annotate(@title || attrs["name"].presence || source_event.name)
      end

      raw.sub(EVENT_TAG) { event_tag(attrs) }
    end

    def date_attrs
      timezone = source_event&.timezone || "UTC"
      all_day = source_event&.all_day || false
      ends_at = effective_ends_at

      {
        "start" => format_time(@starts_at, timezone, all_day),
        "end" => ends_at && format_time(ends_at, timezone, all_day),
      }
    end

    # Double quotes are dropped from values: a reviewer's title override
    # flows into `name`, and a quote there would end the attribute early and
    # let the rest of the title be read as other event attributes.
    def event_tag(attrs)
      parts = attrs.filter_map { |key, value| %(#{key}="#{value.delete('"')}") if value.present? }
      "[event #{parts.join(" ")}]"
    end

    def format_time(time, timezone, all_day)
      zoned = time.in_time_zone(timezone)
      all_day ? zoned.strftime("%Y-%m-%d") : zoned.strftime("%Y-%m-%d %H:%M")
    end
  end
end
