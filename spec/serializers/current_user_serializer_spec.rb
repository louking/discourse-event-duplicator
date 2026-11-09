# frozen_string_literal: true

require "rails_helper"

RSpec.describe CurrentUserSerializer do
  subject(:serializer) { described_class.new(user, scope: Guardian.new(user), root: false) }

  fab!(:user)
  fab!(:allowed_group, :group)
  fab!(:other_group, :group)

  let(:parsed_json) { JSON.parse(serializer.to_json) }

  before do
    SiteSetting.event_duplicator_enabled = true
    SiteSetting.event_duplicator_allowed_groups = allowed_group.id.to_s
  end

  describe "#event_duplicator_in_allowed_groups" do
    it "is true when the user is in an allowed group" do
      allowed_group.add(user)

      expect(parsed_json["event_duplicator_in_allowed_groups"]).to eq(true)
    end

    it "is true when the user is in one of several allowed groups" do
      SiteSetting.event_duplicator_allowed_groups = "#{other_group.id}|#{allowed_group.id}"
      allowed_group.add(user)

      expect(parsed_json["event_duplicator_in_allowed_groups"]).to eq(true)
    end

    it "is false when the user is in none of the allowed groups" do
      other_group.add(user)

      expect(parsed_json["event_duplicator_in_allowed_groups"]).to eq(false)
    end

    it "is false when the allowed groups list is empty (nobody passes, not unrestricted)" do
      SiteSetting.event_duplicator_allowed_groups = ""
      allowed_group.add(user)

      expect(parsed_json["event_duplicator_in_allowed_groups"]).to eq(false)
    end

    it "is true for any user when the list includes the everyone auto-group" do
      SiteSetting.event_duplicator_allowed_groups = Group::AUTO_GROUPS[:everyone].to_s

      expect(parsed_json["event_duplicator_in_allowed_groups"]).to eq(true)
    end

    it "is not included when event_duplicator_enabled is off" do
      SiteSetting.event_duplicator_enabled = false

      expect(parsed_json).not_to have_key("event_duplicator_in_allowed_groups")
    end
  end
end
