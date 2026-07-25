# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseEventDuplicator::TopicDeduplicator do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:category)
  fab!(:grand_prix) { Fabricate(:tag, name: "grand-prix") }
  fab!(:signature_race) { Fabricate(:tag, name: "signature-race") }

  let(:guardian) { Guardian.new(user) }

  def topic_with_event(tags:, category: self.category, starts_at: 1.day.from_now)
    topic = Fabricate(:topic, category: category, tags: tags)
    post = Fabricate(:post, topic: topic)
    Fabricate(:event, post: post, original_starts_at: starts_at.iso8601)
    topic
  end

  it "returns a topic tagged with more than one matching tag only once" do
    topic = topic_with_event(tags: [grand_prix, signature_race])

    result = described_class.new(tags: %w[grand-prix signature-race], guardian: guardian).call

    expect(result).to contain_exactly(topic)
  end

  it "excludes topics without a discourse-calendar event" do
    topic_without_event = Fabricate(:topic, category: category, tags: [grand_prix])

    result = described_class.new(tags: %w[grand-prix], guardian: guardian).call

    expect(result).not_to include(topic_without_event)
  end

  it "restricts to the given category when one is provided" do
    matching = topic_with_event(tags: [grand_prix])
    other_category = Fabricate(:category)
    topic_with_event(tags: [grand_prix], category: other_category)

    result = described_class.new(tags: %w[grand-prix], guardian: guardian, category: category).call

    expect(result).to contain_exactly(matching)
  end

  it "excludes topics in categories not visible to the guardian" do
    restricted_group = Fabricate(:group)
    restricted_category = Fabricate(:private_category, group: restricted_group)
    topic_with_event(tags: [grand_prix], category: restricted_category)

    result = described_class.new(tags: %w[grand-prix], guardian: guardian).call

    expect(result).to be_empty
  end

  it "restricts to events starting within the given range" do
    too_early = topic_with_event(tags: [grand_prix], starts_at: 1.year.ago)
    in_range = topic_with_event(tags: [grand_prix], starts_at: 1.day.from_now)
    too_late = topic_with_event(tags: [grand_prix], starts_at: 1.year.from_now)

    result =
      described_class.new(
        tags: %w[grand-prix],
        guardian: guardian,
        starts_after: 1.week.ago,
        starts_before: 1.week.from_now,
      ).call

    expect(result).to contain_exactly(in_range)
    expect(result).not_to include(too_early, too_late)
  end
end
