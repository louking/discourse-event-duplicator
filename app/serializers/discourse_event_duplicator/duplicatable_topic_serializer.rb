# frozen_string_literal: true

module ::DiscourseEventDuplicator
  class DuplicatableTopicSerializer < ApplicationSerializer
    attributes :id,
               :title,
               :tags,
               :original_start,
               :original_end,
               :proposed_start,
               :proposed_end,
               :already_duplicated,
               :existing_duplicate_topic_id,
               :existing_duplicate_topic_url,
               :selected

    def tags
      object.tags.map(&:name)
    end

    # The source event's own date(s), for the review UI to show alongside
    # the proposed (shifted) date(s) -- "this is the one you're copying".
    def original_start
      object.first_post&.event&.starts_at
    end

    def original_end
      object.first_post&.event&.ends_at
    end

    def proposed_start
      proposed_dates&.dig(:starts_at)
    end

    def proposed_end
      proposed_dates&.dig(:ends_at)
    end

    def already_duplicated
      existing_duplicate.present?
    end

    def existing_duplicate_topic_id
      existing_duplicate && existing_duplicate["topic_id"]
    end

    def existing_duplicate_topic_url
      existing_duplicate && "/t/#{existing_duplicate["topic_id"]}"
    end

    # Unchecked by default when this topic was already duplicated to the
    # same target occurrence, so a second series run doesn't silently
    # re-select it -- see DuplicationTracker.
    def selected
      !already_duplicated
    end

    private

    def proposed_dates
      options.dig(:proposed_dates, object.id)
    end

    def existing_duplicate
      options.dig(:existing_duplicates, object.id)
    end
  end
end
