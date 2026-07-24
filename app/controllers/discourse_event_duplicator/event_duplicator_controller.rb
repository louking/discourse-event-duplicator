# frozen_string_literal: true

module ::DiscourseEventDuplicator
  class EventDuplicatorController < ApplicationController
    requires_login

    # GET /event-duplicator/tags/:tag_name/topics
    #
    # Lists the topics that back a "series" duplication: every topic tagged
    # with the given tag (or any of `additional_tags`), deduped so a topic
    # carrying more than one matching tag is only listed once.
    def tagged_topics
      category = find_category!
      ensure_can_duplicate_into!(category)

      # TODO: query TopicQuery for topics in `category` tagged with
      # `params[:tag_name]` (and any `params[:additional_tags]`), dedupe by
      # topic id, and serialize alongside their discourse-calendar event dates.
      render json: { topics: [] }
    end

    # GET /event-duplicator/topics/:topic_id/proposed_dates
    #
    # Computes the proposed next-occurrence date(s) for one or more topics,
    # for the reviewer to edit/confirm before duplication.
    def proposed_dates
      topic = find_topic!
      ensure_can_duplicate_into!(topic.category)

      # TODO: read the discourse-calendar custom fields for `topic`'s event,
      # shift them forward (default: +1 year), and return the proposal.
      render json: { topic_id: topic.id, proposed_start: nil, proposed_end: nil }
    end

    # POST /event-duplicator/duplicate
    #
    # Performs the duplication for the reviewed/edited set of topics.
    def duplicate
      category = find_category!
      ensure_can_duplicate_into!(category)

      # TODO: for each reviewed item in params[:items], create the duplicate
      # topic/post and its discourse-calendar event with the confirmed dates.
      render json: { duplicated: [] }
    end

    private

    # Authorization is entirely category-based: there is no plugin-specific
    # group or role. Anyone who can create a topic in the target category
    # (per Discourse's own category permissions) may duplicate events into it.
    def ensure_can_duplicate_into!(category)
      raise Discourse::InvalidAccess unless guardian.can_create_topic_on_category?(category)
    end

    def find_category!
      category_id = params[:category_id] || params.dig(:duplicate, :category_id)
      category = Category.find_by(id: category_id)
      raise Discourse::NotFound if category.blank?
      category
    end

    def find_topic!
      topic = Topic.find_by(id: params[:topic_id])
      raise Discourse::NotFound if topic.blank?
      topic
    end
  end
end
