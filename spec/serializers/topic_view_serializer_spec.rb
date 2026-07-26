# frozen_string_literal: true

require "rails_helper"

RSpec.describe TopicViewSerializer do
  subject(:serializer) { described_class.new(TopicView.new(topic), scope: Guardian.new, root: false) }

  fab!(:topic)
  fab!(:post) { Fabricate(:post, topic: topic) }

  let(:parsed_json) { JSON.parse(serializer.to_json) }

  before do
    SiteSetting.event_duplicator_enabled = true
    SiteSetting.calendar_enabled = true
    SiteSetting.discourse_post_event_enabled = true
  end

  describe "#event_duplicator_has_event" do
    it "is true when the topic's first post has a discourse-calendar event" do
      Fabricate(:event, post: post)

      expect(parsed_json["event_duplicator_has_event"]).to eq(true)
    end

    it "is false when the topic has no discourse-calendar event" do
      expect(parsed_json["event_duplicator_has_event"]).to eq(false)
    end

    it "is not included when event_duplicator_enabled is off" do
      SiteSetting.event_duplicator_enabled = false

      expect(parsed_json).not_to have_key("event_duplicator_has_event")
    end
  end
end
