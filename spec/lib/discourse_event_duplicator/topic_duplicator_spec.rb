# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseEventDuplicator::TopicDuplicator do
  fab!(:actor) { Fabricate(:admin, refresh_auto_groups: true) }
  fab!(:category)
  fab!(:tag) { Fabricate(:tag, name: "grand-prix") }

  fab!(:source_topic) { Fabricate(:topic, category: category, tags: [tag], title: "Monaco Grand Prix") }
  fab!(:source_post) { Fabricate(:post, topic: source_topic) }
  fab!(:source_event) do
    Fabricate(
      :event,
      post: source_post,
      name: "Monaco Grand Prix",
      timezone: "Europe/Monaco",
      original_starts_at: "2026-05-24 13:00",
    )
  end

  let(:starts_at) { Time.find_zone("Europe/Monaco").parse("2027-05-23 13:00") }

  before do
    SiteSetting.calendar_enabled = true
    SiteSetting.discourse_post_event_enabled = true
  end

  it "reuses the source topic's title despite Discourse's default duplicate-title check" do
    expect(SiteSetting.allow_duplicate_topic_titles).to eq(false)

    new_topic = described_class.new(source_topic: source_topic, actor: actor, starts_at: starts_at).call

    expect(new_topic.title).to eq("Monaco Grand Prix")
  end

  it "creates a new topic in the same category and tags" do
    new_topic = described_class.new(source_topic: source_topic, actor: actor, starts_at: starts_at).call

    expect(new_topic.category_id).to eq(category.id)
    expect(new_topic.tags).to contain_exactly(tag)
  end

  it "creates the duplicate's event at the confirmed start date" do
    new_topic = described_class.new(source_topic: source_topic, actor: actor, starts_at: starts_at).call

    event = new_topic.first_post.reload.event
    expect(event).to be_present
    expect(event.original_starts_at).to eq_time(starts_at)
  end

  it "authors the new topic as the acting user, not the source topic's author" do
    new_topic = described_class.new(source_topic: source_topic, actor: actor, starts_at: starts_at).call

    expect(new_topic.user_id).to eq(actor.id)
  end

  it "carries over the source event's name and timezone" do
    new_topic = described_class.new(source_topic: source_topic, actor: actor, starts_at: starts_at).call

    event = new_topic.first_post.reload.event
    expect(event.name).to eq("Monaco Grand Prix")
    expect(event.timezone).to eq("Europe/Monaco")
  end

  describe "end date" do
    fab!(:source_topic_with_duration) do
      Fabricate(:topic, category: category, tags: [tag], title: "Silverstone Grand Prix")
    end
    fab!(:source_post_with_duration) { Fabricate(:post, topic: source_topic_with_duration) }
    fab!(:source_event_with_duration) do
      Fabricate(
        :event,
        post: source_post_with_duration,
        name: "Silverstone Grand Prix",
        timezone: "Europe/London",
        original_starts_at: "2026-05-24 13:00",
        original_ends_at: "2026-05-24 15:00",
      )
    end

    it "carries over the source event's duration rather than accepting an end date directly" do
      new_topic =
        described_class.new(
          source_topic: source_topic_with_duration,
          actor: actor,
          starts_at: starts_at,
        ).call

      event = new_topic.first_post.reload.event
      expect(event.original_ends_at).to eq_time(starts_at + 2.hours)
    end

    it "leaves the end date unset when the source event had none" do
      new_topic = described_class.new(source_topic: source_topic, actor: actor, starts_at: starts_at).call

      event = new_topic.first_post.reload.event
      expect(event.original_ends_at).to be_nil
    end
  end

  describe "title:" do
    it "overrides the source topic's title and the event's name" do
      new_topic =
        described_class.new(
          source_topic: source_topic,
          actor: actor,
          starts_at: starts_at,
          title: "Monaco Grand Prix 2027",
        ).call

      expect(new_topic.title).to eq("Monaco Grand Prix 2027")
      expect(new_topic.first_post.reload.event.name).to eq("Monaco Grand Prix 2027")
    end

    it "still applies the tbd annotation on top of the override" do
      new_topic =
        described_class.new(
          source_topic: source_topic,
          actor: actor,
          starts_at: starts_at,
          title: "Monaco Grand Prix 2027",
          tbd: true,
        ).call

      expect(new_topic.title).to eq("Monaco Grand Prix 2027 (date TBD)")
      expect(new_topic.first_post.reload.event.name).to eq("Monaco Grand Prix 2027 (date TBD)")
    end

    it "falls back to the source topic's title when blank" do
      new_topic =
        described_class.new(source_topic: source_topic, actor: actor, starts_at: starts_at, title: "").call

      expect(new_topic.title).to eq("Monaco Grand Prix")
    end
  end

  describe "tbd: true" do
    it "appends the annotation to the duplicate's title and event name" do
      new_topic =
        described_class.new(source_topic: source_topic, actor: actor, starts_at: starts_at, tbd: true).call

      expect(new_topic.title).to eq("Monaco Grand Prix (date TBD)")
      expect(new_topic.first_post.reload.event.name).to eq("Monaco Grand Prix (date TBD)")
    end

    it "does not double up the annotation if the source topic already carries it" do
      source_topic.update!(title: "Monaco Grand Prix (date TBD)")

      new_topic =
        described_class.new(source_topic: source_topic, actor: actor, starts_at: starts_at, tbd: true).call

      expect(new_topic.title).to eq("Monaco Grand Prix (date TBD)")
    end
  end

  describe "tbd: false (default)" do
    it "strips a stale annotation carried over from the source topic" do
      source_topic.update!(title: "Monaco Grand Prix (date TBD)")

      new_topic = described_class.new(source_topic: source_topic, actor: actor, starts_at: starts_at).call

      expect(new_topic.title).to eq("Monaco Grand Prix")
    end
  end
end
