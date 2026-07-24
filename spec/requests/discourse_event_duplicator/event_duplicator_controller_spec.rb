# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseEventDuplicator::EventDuplicatorController do
  fab!(:restricted_group, :group)
  # refresh_auto_groups: true is required for the fabricated user to actually
  # land in the trust_level_N auto groups (Fabricate(:user) alone sets the
  # trust_level column but skips the group sync) -- without it these users
  # fail the site-wide `create_topic_allowed_groups` gate regardless of
  # category permissions, which made this spec fail against a real guardian
  # check rather than exercising the category-permission boundary it's for.
  fab!(:member) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:non_member) { Fabricate(:user, refresh_auto_groups: true) }

  fab!(:category) do
    Fabricate(:category).tap do |c|
      c.set_permissions(restricted_group.id => CategoryGroup.permission_types[:full])
      c.save!
    end
  end

  before do
    SiteSetting.event_duplicator_enabled = true
    restricted_group.add(member)
  end

  describe "#tagged_topics" do
    # Authorization is entirely category-based (no plugin-specific group):
    # anyone who can create a topic in the category may duplicate into it.
    context "when the user can create topics in the category" do
      before { sign_in(member) }

      it "succeeds" do
        get "/event-duplicator/tags/grand-prix/topics.json", params: { category_id: category.id }

        expect(response.status).to eq(200)
      end
    end

    context "when the user cannot create topics in the category" do
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
  end
end
