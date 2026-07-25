# frozen_string_literal: true

module ::DiscourseEventDuplicator
  class EventDuplicatorController < ApplicationController
    requires_login

    # GET /event-duplicator/tags/:tag_name/topics
    #
    # Lists the topics that back a "series" duplication: every topic tagged
    # with the given tag (or any of `additional_tags`), deduped so a topic
    # carrying more than one matching tag is only listed once, optionally
    # restricted to events starting within `starts_after`/`starts_before`.
    def tagged_topics
      category = find_category!
      ensure_can_duplicate_into!(category)

      tags = [params[:tag_name], *Array(params[:additional_tags])].compact
      topics =
        TopicDeduplicator.new(
          tags: tags,
          guardian: guardian,
          category: category,
          starts_after: parse_time(params[:starts_after]),
          starts_before: parse_time(params[:starts_before]),
        ).call

      strategy = resolve_strategy(params[:date_strategy])
      proposed = topics.each_with_object({}) { |topic, h| h[topic.id] = proposed_dates_for(topic, strategy) }
      existing_duplicates =
        topics.each_with_object({}) do |topic, h|
          h[topic.id] = DuplicationTracker.existing_duplicate_for(
            source_topic: topic,
            target_starts_at: proposed[topic.id][:starts_at],
          )
        end

      render_serialized(
        topics,
        DuplicatableTopicSerializer,
        root: "topics",
        proposed_dates: proposed,
        existing_duplicates: existing_duplicates,
      )
    end

    # GET /event-duplicator/topics/:topic_id/proposed_dates
    #
    # Computes the proposed next-occurrence date(s) for one topic, for the
    # reviewer to edit/confirm before duplication.
    def proposed_dates
      topic = find_topic!
      ensure_can_duplicate_into!(topic.category)

      event = topic.first_post&.event
      raise Discourse::NotFound if event.blank?

      strategy = resolve_strategy(params[:date_strategy])
      proposed = DateShifter.new(starts_at: event.starts_at, ends_at: event.ends_at, strategy: strategy).call

      render json: {
               topic_id: topic.id,
               title: topic.title,
               original_start: event.starts_at,
               original_end: event.ends_at,
               proposed_start: proposed[:starts_at],
               proposed_end: proposed[:ends_at],
             }
    end

    # GET /event-duplicator/topics/:topic_id/composer_prefill
    #
    # Builds the title/raw body/category/tags a duplicate of this topic
    # would have at the reviewer's edited start date/title/TBD flag,
    # without creating anything -- the frontend uses this to pre-fill the
    # real Discourse composer so the reviewer finishes and posts it
    # themselves (single-topic duplication only; see TopicDuplicator#preview
    # for why that means normal topic-creation validation applies here,
    # unlike the direct-create path below).
    def composer_prefill
      topic = find_topic!
      ensure_can_duplicate_into!(topic.category)

      starts_at = parse_time(params[:starts_at])
      raise Discourse::InvalidParameters if starts_at.blank?

      preview =
        TopicDuplicator.new(
          source_topic: topic,
          actor: current_user,
          starts_at: starts_at,
          tbd: ActiveModel::Type::Boolean.new.cast(params[:tbd]),
          title: params[:title].presence,
        ).preview

      render json: preview
    end

    # POST /event-duplicator/topics/:topic_id/record_duplicate
    #
    # Called by the frontend once the reviewer finishes the pre-filled
    # composer opened via #composer_prefill and Discourse creates the real
    # topic through its normal composer/PostCreator path -- unlike
    # #duplicate below, nothing else tells DuplicationTracker about a
    # composer-created duplicate, so the frontend reports it back here.
    # `starts_at` is derived from the *new* topic's own event rather than
    # trusted from the request, and the new topic must actually have been
    # authored by the current user, so a forged `new_topic_id` can't record
    # a bogus tracker entry against a topic this user doesn't own.
    def record_duplicate
      topic = find_topic!
      ensure_can_duplicate_into!(topic.category)

      new_topic = Topic.find_by(id: params[:new_topic_id])
      raise Discourse::NotFound if new_topic.blank?
      raise Discourse::InvalidAccess unless new_topic.user_id == current_user.id

      starts_at = new_topic.first_post&.event&.starts_at
      raise Discourse::NotFound if starts_at.blank?

      DuplicationTracker.record!(source_topic: topic, new_topic: new_topic, starts_at: starts_at)

      render json: success_json
    end

    # POST /event-duplicator/duplicate
    #
    # Performs the duplication for the reviewed/edited set of topics. Each
    # item is authorized and checked against DuplicationTracker
    # independently -- items may span categories, so the top-level request
    # can't be authorized once for all of them.
    def duplicate
      duplicated = []
      skipped = []

      Array(params[:items]).each do |item|
        topic = Topic.find_by(id: item[:topic_id])
        raise Discourse::NotFound if topic.blank?

        ensure_can_duplicate_into!(topic.category)

        starts_at = parse_time(item[:starts_at])
        force = ActiveModel::Type::Boolean.new.cast(item[:force])
        tbd = ActiveModel::Type::Boolean.new.cast(item[:tbd])
        title = item[:title].presence

        existing = DuplicationTracker.existing_duplicate_for(source_topic: topic, target_starts_at: starts_at)
        if existing && !force
          skipped << {
            topic_id: topic.id,
            reason: "already_duplicated",
            existing_duplicate_topic_id: existing["topic_id"],
          }
          next
        end

        begin
          new_topic =
            TopicDuplicator.new(
              source_topic: topic,
              actor: current_user,
              starts_at: starts_at,
              tbd: tbd,
              title: title,
            ).call
          DuplicationTracker.record!(source_topic: topic, new_topic: new_topic, starts_at: starts_at)
          duplicated << { topic_id: topic.id, new_topic_id: new_topic.id, new_topic_url: new_topic.relative_url }
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
          skipped << { topic_id: topic.id, reason: e.message }
        end
      end

      render json: { duplicated: duplicated, skipped: skipped }
    end

    private

    # Authorization is category-based *and* gated by an explicit allowlist of
    # groups: a user may duplicate into a category only if Discourse's own
    # category permissions allow them to create a topic there AND they
    # belong to one of the groups in `event_duplicator_allowed_groups`
    # (default: staff).
    def ensure_can_duplicate_into!(category)
      raise Discourse::InvalidAccess unless can_duplicate_into?(category)
    end

    def can_duplicate_into?(category)
      guardian.can_create_topic_on_category?(category) &&
        guardian.user.in_any_groups?(SiteSetting.event_duplicator_allowed_groups_map)
    end

    def resolve_strategy(param)
      (param.presence || SiteSetting.event_duplicator_default_date_strategy).to_sym
    end

    def proposed_dates_for(topic, strategy)
      event = topic.first_post&.event
      DateShifter.new(starts_at: event&.starts_at, ends_at: event&.ends_at, strategy: strategy).call
    end

    def parse_time(value)
      value.present? ? Time.zone.parse(value) : nil
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
