# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseEventDuplicator::DuplicationTracker do
  fab!(:source_topic, :topic)
  fab!(:duplicate_topic, :topic)

  it "finds a recorded duplicate landing in the same target year" do
    described_class.record!(
      source_topic: source_topic,
      new_topic: duplicate_topic,
      starts_at: Time.zone.parse("2027-05-15 13:00"),
    )

    found =
      described_class.existing_duplicate_for(
        source_topic: source_topic,
        target_starts_at: Time.zone.parse("2027-06-01 09:00"),
      )

    expect(found["topic_id"]).to eq(duplicate_topic.id)
  end

  it "returns nil when no duplicate was recorded for that year" do
    described_class.record!(
      source_topic: source_topic,
      new_topic: duplicate_topic,
      starts_at: Time.zone.parse("2027-05-15 13:00"),
    )

    found =
      described_class.existing_duplicate_for(
        source_topic: source_topic,
        target_starts_at: Time.zone.parse("2028-05-15 13:00"),
      )

    expect(found).to be_nil
  end

  it "returns nil when no target date is given" do
    found = described_class.existing_duplicate_for(source_topic: source_topic, target_starts_at: nil)

    expect(found).to be_nil
  end

  it "accumulates multiple recorded duplications" do
    other_duplicate_topic = Fabricate(:topic)

    described_class.record!(
      source_topic: source_topic,
      new_topic: duplicate_topic,
      starts_at: Time.zone.parse("2027-05-15 13:00"),
    )
    described_class.record!(
      source_topic: source_topic,
      new_topic: other_duplicate_topic,
      starts_at: Time.zone.parse("2028-05-13 13:00"),
    )

    expect(
      described_class.existing_duplicate_for(
        source_topic: source_topic,
        target_starts_at: Time.zone.parse("2027-05-01 00:00"),
      )["topic_id"],
    ).to eq(duplicate_topic.id)
    expect(
      described_class.existing_duplicate_for(
        source_topic: source_topic,
        target_starts_at: Time.zone.parse("2028-05-01 00:00"),
      )["topic_id"],
    ).to eq(other_duplicate_topic.id)
  end

  describe "#forget!" do
    it "removes the duplicate's entry from its source's tracker, freeing the occurrence back up" do
      described_class.record!(
        source_topic: source_topic,
        new_topic: duplicate_topic,
        starts_at: Time.zone.parse("2027-05-15 13:00"),
      )

      described_class.forget!(duplicate_topic: duplicate_topic)

      # forget! re-fetches the source topic as its own AR object internally
      # (see source_topic_for), so this spec's own `source_topic` reference
      # needs reloading to see that write -- exactly as a fresh request in
      # the real app would.
      found =
        described_class.existing_duplicate_for(
          source_topic: source_topic.reload,
          target_starts_at: Time.zone.parse("2027-05-15 13:00"),
        )
      expect(found).to be_nil
    end

    it "leaves other recorded duplications on the same source untouched" do
      other_duplicate_topic = Fabricate(:topic)
      described_class.record!(
        source_topic: source_topic,
        new_topic: duplicate_topic,
        starts_at: Time.zone.parse("2027-05-15 13:00"),
      )
      described_class.record!(
        source_topic: source_topic,
        new_topic: other_duplicate_topic,
        starts_at: Time.zone.parse("2028-05-13 13:00"),
      )

      described_class.forget!(duplicate_topic: duplicate_topic)

      found =
        described_class.existing_duplicate_for(
          source_topic: source_topic.reload,
          target_starts_at: Time.zone.parse("2028-05-01 00:00"),
        )
      expect(found["topic_id"]).to eq(other_duplicate_topic.id)
    end

    it "is a no-op for a topic that was never recorded as a duplicate" do
      plain_topic = Fabricate(:topic)

      expect { described_class.forget!(duplicate_topic: plain_topic) }.not_to raise_error
    end

    it "is a no-op when called twice (idempotent, since :topic_destroyed and :topic_trashed both fire)" do
      described_class.record!(
        source_topic: source_topic,
        new_topic: duplicate_topic,
        starts_at: Time.zone.parse("2027-05-15 13:00"),
      )

      described_class.forget!(duplicate_topic: duplicate_topic)
      expect { described_class.forget!(duplicate_topic: duplicate_topic) }.not_to raise_error
    end
  end

  describe "#restore!" do
    it "re-adds the duplicate's entry after forget!, undoing it" do
      described_class.record!(
        source_topic: source_topic,
        new_topic: duplicate_topic,
        starts_at: Time.zone.parse("2027-05-15 13:00"),
      )
      described_class.forget!(duplicate_topic: duplicate_topic)

      described_class.restore!(duplicate_topic: duplicate_topic)

      found =
        described_class.existing_duplicate_for(
          source_topic: source_topic.reload,
          target_starts_at: Time.zone.parse("2027-05-15 13:00"),
        )
      expect(found["topic_id"]).to eq(duplicate_topic.id)
    end

    it "is idempotent -- calling it twice doesn't add a duplicate entry" do
      described_class.record!(
        source_topic: source_topic,
        new_topic: duplicate_topic,
        starts_at: Time.zone.parse("2027-05-15 13:00"),
      )
      described_class.forget!(duplicate_topic: duplicate_topic)

      described_class.restore!(duplicate_topic: duplicate_topic)
      described_class.restore!(duplicate_topic: duplicate_topic)

      entries = source_topic.reload.custom_fields[described_class::FIELD_NAME]
      expect(entries.count { |e| e["topic_id"] == duplicate_topic.id }).to eq(1)
    end

    it "is a no-op for a topic that was never recorded as a duplicate" do
      plain_topic = Fabricate(:topic)

      expect { described_class.restore!(duplicate_topic: plain_topic) }.not_to raise_error
    end
  end

  describe "plugin.rb's DiscourseEvent hooks (via PostDestroyer, the real deletion code path)" do
    fab!(:admin)
    fab!(:duplicate_first_post) { Fabricate(:post, topic: duplicate_topic) }

    before do
      # Plugin::Instance#on gates every DiscourseEvent hook on the plugin
      # being enabled (see plugin.rb) -- without this, the hooks silently
      # no-op and this whole describe block would pass for the wrong reason
      # (nothing runs, nothing raises).
      SiteSetting.event_duplicator_enabled = true

      described_class.record!(
        source_topic: source_topic,
        new_topic: duplicate_topic,
        starts_at: Time.zone.parse("2027-05-15 13:00"),
      )
    end

    it "frees the source topic's tracked occurrence when the duplicate topic is trashed" do
      PostDestroyer.new(admin, duplicate_first_post).destroy

      found =
        described_class.existing_duplicate_for(
          source_topic: source_topic.reload,
          target_starts_at: Time.zone.parse("2027-05-15 13:00"),
        )
      expect(found).to be_nil
    end

    it "restores the tracked occurrence when the duplicate topic is recovered" do
      destroyer = PostDestroyer.new(admin, duplicate_first_post)
      destroyer.destroy
      destroyer.recover

      found =
        described_class.existing_duplicate_for(
          source_topic: source_topic.reload,
          target_starts_at: Time.zone.parse("2027-05-15 13:00"),
        )
      expect(found["topic_id"]).to eq(duplicate_topic.id)
    end

    it "leaves the tracker alone when an unrelated topic is trashed" do
      unrelated_post = Fabricate(:post)
      PostDestroyer.new(admin, unrelated_post).destroy

      found =
        described_class.existing_duplicate_for(
          source_topic: source_topic,
          target_starts_at: Time.zone.parse("2027-05-15 13:00"),
        )
      expect(found["topic_id"]).to eq(duplicate_topic.id)
    end
  end
end
