# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseEventDuplicator::TopicDuplicator do
  fab!(:actor) { Fabricate(:admin, refresh_auto_groups: true) }
  fab!(:category)
  fab!(:tag) { Fabricate(:tag, name: "grand-prix") }

  fab!(:source_topic) do
    Fabricate(:topic, category: category, tags: [tag], title: "Monaco Grand Prix")
  end
  fab!(:source_post) { Fabricate(:post, topic: source_topic) }
  fab!(:source_event) do
    write_event_tag!(
      Fabricate(
        :event,
        post: source_post,
        name: "Monaco Grand Prix",
        timezone: "Europe/Monaco",
        original_starts_at: "2026-05-24 13:00",
      ),
    )
  end

  let(:starts_at) { Time.find_zone("Europe/Monaco").parse("2027-05-23 13:00") }

  before do
    enable_events_plugin!
    SiteSetting.discourse_post_event_enabled = true
  end

  it "reuses the source topic's title despite Discourse's default duplicate-title check" do
    expect(SiteSetting.allow_duplicate_topic_titles).to eq(false)

    new_topic =
      described_class.new(source_topic: source_topic, actor: actor, starts_at: starts_at).call

    expect(new_topic.title).to eq("Monaco Grand Prix")
  end

  it "creates a new topic in the same category and tags" do
    new_topic =
      described_class.new(source_topic: source_topic, actor: actor, starts_at: starts_at).call

    expect(new_topic.category_id).to eq(category.id)
    expect(new_topic.tags).to contain_exactly(tag)
  end

  it "creates the duplicate's event at the confirmed start date" do
    new_topic =
      described_class.new(source_topic: source_topic, actor: actor, starts_at: starts_at).call

    event = new_topic.first_post.reload.event
    expect(event).to be_present
    expect(event.original_starts_at).to eq_time(starts_at)
  end

  it "authors the new topic as the acting user, not the source topic's author" do
    new_topic =
      described_class.new(source_topic: source_topic, actor: actor, starts_at: starts_at).call

    expect(new_topic.user_id).to eq(actor.id)
  end

  it "carries over the source event's name and timezone" do
    new_topic =
      described_class.new(source_topic: source_topic, actor: actor, starts_at: starts_at).call

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
      write_event_tag!(
        Fabricate(
          :event,
          post: source_post_with_duration,
          name: "Silverstone Grand Prix",
          timezone: "Europe/London",
          original_starts_at: "2026-05-24 13:00",
          original_ends_at: "2026-05-24 15:00",
        ),
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
      new_topic =
        described_class.new(source_topic: source_topic, actor: actor, starts_at: starts_at).call

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
        described_class.new(
          source_topic: source_topic,
          actor: actor,
          starts_at: starts_at,
          title: "",
        ).call

      expect(new_topic.title).to eq("Monaco Grand Prix")
    end
  end

  describe "tbd: true" do
    it "appends the annotation to the duplicate's title and event name" do
      new_topic =
        described_class.new(
          source_topic: source_topic,
          actor: actor,
          starts_at: starts_at,
          tbd: true,
        ).call

      expect(new_topic.title).to eq("Monaco Grand Prix (date TBD)")
      expect(new_topic.first_post.reload.event.name).to eq("Monaco Grand Prix (date TBD)")
    end

    it "does not double up the annotation if the source topic already carries it" do
      source_topic.update!(title: "Monaco Grand Prix (date TBD)")

      new_topic =
        described_class.new(
          source_topic: source_topic,
          actor: actor,
          starts_at: starts_at,
          tbd: true,
        ).call

      expect(new_topic.title).to eq("Monaco Grand Prix (date TBD)")
    end

    it "inserts its own separating space rather than requiring one in the site setting" do
      # Discourse's SiteSetting::Update service strips leading/trailing
      # whitespace from every setting value on save
      # (app/services/site_setting/update.rb), so a real admin-set value can
      # never actually have a leading space here -- exercised without one to
      # match what's really stored, rather than what an admin might type.
      SiteSetting.event_duplicator_tbd_annotation = "(TENTATIVE)"

      new_topic =
        described_class.new(
          source_topic: source_topic,
          actor: actor,
          starts_at: starts_at,
          tbd: true,
        ).call

      expect(new_topic.title).to eq("Monaco Grand Prix (TENTATIVE)")
    end
  end

  describe "tbd: false (default)" do
    it "strips a stale annotation carried over from the source topic" do
      source_topic.update!(title: "Monaco Grand Prix (date TBD)")

      new_topic =
        described_class.new(source_topic: source_topic, actor: actor, starts_at: starts_at).call

      expect(new_topic.title).to eq("Monaco Grand Prix")
    end
  end

  describe "source post text" do
    fab!(:source_topic_with_text) do
      Fabricate(:topic, category: category, tags: [tag], title: "Belgian Spa Grand Prix")
    end
    fab!(:source_post_with_text) do
      # update_column skips discourse-calendar's post validation and event
      # sync; the event row is fabricated separately below.
      Fabricate(:post, topic: source_topic_with_text).tap do |post|
        post.update_column(:raw, <<~RAW.strip)
          Registration opens in March.

          [event start="2026-08-30 15:00" end="2026-08-30 17:00" name="Spa Grand Prix" timezone="Europe/Brussels" location="Circuit de Spa-Francorchamps"]
          [/event]

          See the [course map](https://example.com/map).
        RAW
      end
    end
    fab!(:source_event_with_text) do
      Fabricate(
        :event,
        post: source_post_with_text,
        name: "Spa Grand Prix",
        timezone: "Europe/Brussels",
        original_starts_at: "2026-08-30 15:00",
        original_ends_at: "2026-08-30 17:00",
      )
    end

    let(:spa_starts_at) { Time.find_zone("Europe/Brussels").parse("2027-08-29 15:00") }

    def duplicate(**opts)
      described_class.new(
        source_topic: source_topic_with_text,
        actor: actor,
        starts_at: spa_starts_at,
        **opts,
      ).call
    end

    it "copies the text around the event block" do
      raw = duplicate.first_post.raw

      expect(raw).to start_with("Registration opens in March.\n\n[event ")
      expect(raw).to end_with("[/event]\n\nSee the [course map](https://example.com/map).")
    end

    it "rewrites the event tag's dates and keeps its other attributes" do
      raw = duplicate.first_post.raw

      expect(raw).to include('start="2027-08-29 15:00"')
      expect(raw).to include('end="2027-08-29 17:00"')
      expect(raw).to include('location="Circuit de Spa-Francorchamps"')
      expect(raw).not_to include("2026-08-30")
    end

    it "creates the duplicate's event from the rewritten tag" do
      event = duplicate.first_post.reload.event

      expect(event.original_starts_at).to eq_time(spa_starts_at)
      expect(event.location).to eq("Circuit de Spa-Francorchamps")
    end

    it "applies the title override and tbd annotation to the tag's name" do
      raw = duplicate(title: "Belgian Grand Prix", tbd: true).first_post.raw

      expect(raw).to include('name="Belgian Grand Prix (date TBD)"')
    end

    it "drops double quotes from a title override so it can't add event attributes" do
      raw = duplicate(title: 'Spa" location="Elsewhere').first_post.raw

      expect(raw).to include('name="Spa location=Elsewhere"')
      expect(raw).to include('location="Circuit de Spa-Francorchamps"')
    end

    it "accepts unquoted and single-quoted attribute values in the source tag" do
      source_topic_with_text.first_post.update_column(
        :raw,
        "[event start=\"2026-08-30 15:00\" end=\"2026-08-30 17:00\" " \
          "location='Circuit de Spa-Francorchamps' status=public timezone=Europe/Brussels]\n" \
          "[/event]",
      )

      raw = duplicate.first_post.raw

      expect(raw).to include('start="2027-08-29 15:00"')
      expect(raw).to include('location="Circuit de Spa-Francorchamps"')
      expect(raw).to include('status="public"')
      expect(raw).to include('timezone="Europe/Brussels"')
      expect(raw).not_to include("2026-08-30")
    end
  end

  it "raises instead of creating a topic when the source post has no event tag" do
    source_post.update_column(:raw, "Bring your own water.")

    expect {
      described_class.new(source_topic: source_topic, actor: actor, starts_at: starts_at).call
    }.to raise_error(described_class::MissingEventTag).and not_change { Topic.count }
  end
end
