# frozen_string_literal: true

module ::DiscourseEventDuplicator
  # Records which target occurrences a topic has already been duplicated to,
  # so that a topic matching more than one series tag doesn't get
  # duplicated twice across two separate runs (one per tag).
  #
  # Also stamps the *duplicate* topic itself with a reverse pointer back to
  # its source (SOURCE_FIELD_NAME), so that `forget!`/`restore!` (called
  # from plugin.rb's `on(:topic_trashed)`/`on(:topic_destroyed)`/
  # `on(:topic_recovered)` hooks) can find the right source entry in O(1)
  # rather than scanning every topic that carries FIELD_NAME. Deleting a
  # duplicate makes its source eligible for re-duplication again, as if the
  # duplicate had never been created; recovering it re-locks that
  # eligibility. Topics duplicated before this reverse pointer existed have
  # no SOURCE_FIELD_NAME custom field, so deleting one of those is a no-op
  # here rather than an error -- a known, accepted gap for pre-existing data.
  class DuplicationTracker
    FIELD_NAME = "event_duplicator_duplications"
    SOURCE_FIELD_NAME = "event_duplicator_source"

    def self.record!(source_topic:, new_topic:, starts_at:)
      entries = existing_entries(source_topic)
      entries << { "topic_id" => new_topic.id, "starts_at" => starts_at.iso8601 }
      source_topic.custom_fields[FIELD_NAME] = entries
      source_topic.save_custom_fields(true)

      new_topic.custom_fields[SOURCE_FIELD_NAME] = {
        "topic_id" => source_topic.id,
        "starts_at" => starts_at.iso8601,
      }
      new_topic.save_custom_fields(true)
    end

    # Two duplications landing in the same target year are treated as the
    # same occurrence -- exact-timestamp matching would be too brittle
    # across edited dates and different shift strategies.
    def self.existing_duplicate_for(source_topic:, target_starts_at:)
      return nil unless target_starts_at

      existing_entries(source_topic).find do |entry|
        Time.zone.parse(entry["starts_at"]).year == target_starts_at.year
      end
    end

    # Removes `duplicate_topic`'s entry from its source's tracker. Called on
    # both :topic_trashed (the common, reversible delete) and
    # :topic_destroyed (fires for that *and* a direct permanent delete, so
    # this is a safe, idempotent no-op the second time when both fire for
    # the same ordinary trash).
    def self.forget!(duplicate_topic:)
      source_topic = source_topic_for(duplicate_topic)
      return unless source_topic

      entries = existing_entries(source_topic)
      removed = entries.reject! { |entry| entry["topic_id"] == duplicate_topic.id }
      return unless removed

      source_topic.custom_fields[FIELD_NAME] = entries
      source_topic.save_custom_fields(true)
    end

    # Re-adds `duplicate_topic`'s entry to its source's tracker, undoing
    # `forget!`. Idempotent -- Discourse fires :topic_recovered twice per
    # recovery, and this guards against double-adding the entry.
    def self.restore!(duplicate_topic:)
      source_topic = source_topic_for(duplicate_topic)
      return unless source_topic

      entries = existing_entries(source_topic)
      return if entries.any? { |entry| entry["topic_id"] == duplicate_topic.id }

      source_ref = duplicate_topic.custom_fields[SOURCE_FIELD_NAME]
      entries << { "topic_id" => duplicate_topic.id, "starts_at" => source_ref["starts_at"] }
      source_topic.custom_fields[FIELD_NAME] = entries
      source_topic.save_custom_fields(true)
    end

    def self.existing_entries(source_topic)
      Array.wrap(source_topic.custom_fields[FIELD_NAME])
    end
    private_class_method :existing_entries

    def self.source_topic_for(duplicate_topic)
      source_ref = duplicate_topic.custom_fields[SOURCE_FIELD_NAME]
      return nil unless source_ref

      Topic.find_by(id: source_ref["topic_id"])
    end
    private_class_method :source_topic_for
  end
end
