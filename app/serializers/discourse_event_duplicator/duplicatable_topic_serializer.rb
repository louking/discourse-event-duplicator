# frozen_string_literal: true

module ::DiscourseEventDuplicator
  class DuplicatableTopicSerializer < ApplicationSerializer
    attributes :id, :title, :tags, :proposed_start, :proposed_end, :selected

    def tags
      object.tags.map(&:name)
    end

    # TODO: source from the discourse-calendar post/topic custom fields.
    def proposed_start
      nil
    end

    def proposed_end
      nil
    end

    # Whether this item is checked by default in the review UI.
    def selected
      true
    end
  end
end
