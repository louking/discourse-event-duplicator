# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseEventDuplicator::EventDuplicatorController do
  fab!(:restricted_group) { Fabricate(:group) }
  fab!(:member) { Fabricate(:user) }
  fab!(:non_member) { Fabricate(:user) }

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
