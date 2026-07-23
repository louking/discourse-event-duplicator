# frozen_string_literal: true

module ::DiscourseEventDuplicator
  # Given a list of tags that mark a topic as part of a series (e.g.
  # "grand-prix", "signature-race"), returns each matching topic exactly
  # once, even when a topic carries more than one of the given tags.
  class TopicDeduplicator
    def initialize(tags:)
      @tags = tags
    end

    def call
      raise NotImplementedError, "TopicDeduplicator#call is not implemented yet"
    end
  end
end
