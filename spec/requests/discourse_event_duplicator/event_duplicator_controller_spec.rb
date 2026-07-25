# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseEventDuplicator::EventDuplicatorController do
  fab!(:restricted_group, :group)
  fab!(:allowed_group, :group)
  # refresh_auto_groups: true is required for the fabricated user to actually
  # land in the trust_level_N auto groups (Fabricate(:user) alone sets the
  # trust_level column but skips the group sync) -- without it these users
  # fail the site-wide `create_topic_allowed_groups` gate regardless of
  # category permissions, which made this spec fail against a real guardian
  # check rather than exercising the category-permission boundary it's for.
  fab!(:member) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:category_only_member) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:plugin_only_member) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:non_member) { Fabricate(:user, refresh_auto_groups: true) }

  fab!(:category) do
    Fabricate(:category).tap do |c|
      c.set_permissions(restricted_group.id => CategoryGroup.permission_types[:full])
      c.save!
    end
  end

  before do
    SiteSetting.event_duplicator_enabled = true
    # Default is staff-only; these specs test the AND with category
    # permissions using a dedicated group instead of granting staff.
    SiteSetting.event_duplicator_allowed_groups = allowed_group.id.to_s

    restricted_group.add(member)
    allowed_group.add(member)
    restricted_group.add(category_only_member)
    allowed_group.add(plugin_only_member)
  end

  describe "#tagged_topics" do
    context "when the user has category access and is in the allowed group" do
      before { sign_in(member) }

      it "succeeds" do
        get "/event-duplicator/tags/grand-prix/topics.json", params: { category_id: category.id }

        expect(response.status).to eq(200)
      end
    end

    context "when the user has category access but is not in the allowed group" do
      before { sign_in(category_only_member) }

      it "returns 403" do
        get "/event-duplicator/tags/grand-prix/topics.json", params: { category_id: category.id }

        expect(response.status).to eq(403)
      end
    end

    context "when the user is in the allowed group but lacks category access" do
      before { sign_in(plugin_only_member) }

      it "returns 403" do
        get "/event-duplicator/tags/grand-prix/topics.json", params: { category_id: category.id }

        expect(response.status).to eq(403)
      end
    end

    context "when the user has neither category access nor group membership" do
      before { sign_in(non_member) }

      it "returns 403" do
        get "/event-duplicator/tags/grand-prix/topics.json", params: { category_id: category.id }

        expect(response.status).to eq(403)
      end
    end

    context "when logged out" do
      it "returns 403" do
        get "/event-duplicator/tags/grand-prix/topics.json", params: { category_id: category.id }

        expect(response.status).to eq(403)
      end
    end

    context "with matching topics" do
      fab!(:tag) { Fabricate(:tag, name: "grand-prix") }
      fab!(:topic) { Fabricate(:topic, category: category, tags: [tag]) }
      fab!(:first_post) { Fabricate(:post, topic: topic) }
      fab!(:event) { Fabricate(:event, post: first_post, original_starts_at: "2026-05-24 13:00") }

      before { sign_in(member) }

      it "returns the deduped topics with proposed dates" do
        get "/event-duplicator/tags/grand-prix/topics.json", params: { category_id: category.id }

        json = response.parsed_body
        expect(json["topics"].map { |t| t["id"] }).to contain_exactly(topic.id)
        expect(json["topics"].first["original_start"]).to eq("2026-05-24T13:00:00.000Z")
        expect(json["topics"].first["proposed_start"]).to be_present
        expect(json["topics"].first["selected"]).to eq(true)
      end

      it "flags a topic already duplicated to the same target year as unselected" do
        duplicate_topic = Fabricate(:topic)
        DiscourseEventDuplicator::DuplicationTracker.record!(
          source_topic: topic,
          new_topic: duplicate_topic,
          starts_at: Time.zone.parse("2027-05-24 13:00"),
        )

        get "/event-duplicator/tags/grand-prix/topics.json", params: { category_id: category.id }

        result = response.parsed_body["topics"].first
        expect(result["already_duplicated"]).to eq(true)
        expect(result["existing_duplicate_topic_id"]).to eq(duplicate_topic.id)
        expect(result["selected"]).to eq(false)
      end
    end
  end

  describe "#proposed_dates" do
    fab!(:topic) { Fabricate(:topic, category: category) }
    fab!(:first_post) { Fabricate(:post, topic: topic) }
    fab!(:event) { Fabricate(:event, post: first_post, original_starts_at: "2026-05-24 13:00") }

    context "when authorized" do
      before { sign_in(member) }

      it "returns the shifted proposed dates" do
        get "/event-duplicator/topics/#{topic.id}/proposed_dates.json"

        expect(response.status).to eq(200)
        expect(response.parsed_body["title"]).to eq(topic.title)
        expect(response.parsed_body["original_start"]).to eq("2026-05-24T13:00:00.000Z")
        expect(response.parsed_body["proposed_start"]).to eq("2027-05-24T13:00:00.000Z")
      end
    end

    context "when not authorized" do
      before { sign_in(non_member) }

      it "returns 403" do
        get "/event-duplicator/topics/#{topic.id}/proposed_dates.json"

        expect(response.status).to eq(403)
      end
    end

    context "when the topic has no event" do
      fab!(:topic_without_event) { Fabricate(:topic, category: category) }

      before { sign_in(member) }

      it "returns 404" do
        get "/event-duplicator/topics/#{topic_without_event.id}/proposed_dates.json"

        expect(response.status).to eq(404)
      end
    end
  end

  describe "#duplicate" do
    fab!(:topic) { Fabricate(:topic, category: category, title: "Monaco Grand Prix") }
    fab!(:first_post) { Fabricate(:post, topic: topic) }
    fab!(:event) do
      Fabricate(:event, post: first_post, name: "Monaco Grand Prix", original_starts_at: "2026-05-24 13:00")
    end

    before do
      SiteSetting.calendar_enabled = true
      SiteSetting.discourse_post_event_enabled = true
      # discourse-calendar only lets staff (or members of its own allowed
      # group setting) create [event] blocks; admin is the simplest way to
      # satisfy that for the acting user in this spec.
      member.update!(admin: true)
    end

    context "when authorized" do
      before { sign_in(member) }

      it "creates the duplicate topic" do
        post "/event-duplicator/duplicate.json",
             params: {
               items: [{ topic_id: topic.id, starts_at: "2027-05-24T13:00:00Z" }],
             }

        expect(response.status).to eq(200)
        json = response.parsed_body
        expect(json["duplicated"].length).to eq(1)
        expect(json["skipped"]).to be_empty

        new_topic = Topic.find(json["duplicated"].first["new_topic_id"])
        expect(new_topic.first_post.reload.event.original_starts_at).to eq_time(
          Time.zone.parse("2027-05-24T13:00:00Z"),
        )
      end

      it "annotates the title and event name when tbd is set" do
        post "/event-duplicator/duplicate.json",
             params: {
               items: [{ topic_id: topic.id, starts_at: "2027-05-24T13:00:00Z", tbd: true }],
             }

        new_topic = Topic.find(response.parsed_body["duplicated"].first["new_topic_id"])
        expect(new_topic.title).to eq("Monaco Grand Prix (date TBD)")
        expect(new_topic.first_post.reload.event.name).to eq("Monaco Grand Prix (date TBD)")
      end

      it "applies a title override when given" do
        post "/event-duplicator/duplicate.json",
             params: {
               items: [
                 { topic_id: topic.id, starts_at: "2027-05-24T13:00:00Z", title: "Monaco Grand Prix 2027" },
               ],
             }

        new_topic = Topic.find(response.parsed_body["duplicated"].first["new_topic_id"])
        expect(new_topic.title).to eq("Monaco Grand Prix 2027")
        expect(new_topic.first_post.reload.event.name).to eq("Monaco Grand Prix 2027")
      end

      it "skips an item already duplicated to the same target year unless forced" do
        duplicate_topic = Fabricate(:topic)
        DiscourseEventDuplicator::DuplicationTracker.record!(
          source_topic: topic,
          new_topic: duplicate_topic,
          starts_at: Time.zone.parse("2027-05-24T13:00:00Z"),
        )

        post "/event-duplicator/duplicate.json",
             params: {
               items: [{ topic_id: topic.id, starts_at: "2027-05-24T13:00:00Z" }],
             }

        json = response.parsed_body
        expect(json["duplicated"]).to be_empty
        expect(json["skipped"].first["reason"]).to eq("already_duplicated")
      end
    end

    context "when not authorized" do
      before { sign_in(non_member) }

      it "returns 403" do
        post "/event-duplicator/duplicate.json",
             params: {
               items: [{ topic_id: topic.id, starts_at: "2027-05-24T13:00:00Z" }],
             }

        expect(response.status).to eq(403)
      end
    end
  end
end
