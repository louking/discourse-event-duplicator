# frozen_string_literal: true

module ::DiscourseEventDuplicator
  # Given a list of tags that mark a topic as part of a series (e.g.
  # "grand-prix", "signature-race"), returns each matching topic exactly
  # once, even when a topic carries more than one of the given tags.
  #
  # `category` further restricts the match to that category, and
  # `starts_after`/`starts_before` restrict it to topics whose
  # discourse-calendar event starts within that range -- topics with no
  # event at all (nothing to duplicate) are always excluded.
  class TopicDeduplicator
    def initialize(tags:, guardian:, category: nil, starts_after: nil, starts_before: nil)
      @tags = tags
      @guardian = guardian
      @category = category
      @starts_after = starts_after
      @starts_before = starts_before
    end

    def call
      scope =
        Topic
          .listable_topics
          .secured(@guardian)
          .joins(:tags)
          .where(tags: { name: @tags })
          .distinct
      scope = scope.where(category_id: @category.id) if @category
      scope = scope.includes(first_post: :event)

      scope.select do |topic|
        starts_at = topic.first_post&.event&.starts_at
        next false unless starts_at
        next false if @starts_after && starts_at < @starts_after
        next false if @starts_before && starts_at > @starts_before
        true
      end
    end
  end
end
