# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseEventDuplicator::DateShifter do
  describe "default :calendar_date strategy" do
    it "shifts forward by one year by default" do
      shifter = described_class.new(starts_at: Time.zone.parse("2026-05-24 13:00"))

      expect(shifter.call[:starts_at]).to eq(Time.zone.parse("2027-05-24 13:00"))
    end

    it "shifts both starts_at and ends_at by a custom shift" do
      shifter =
        described_class.new(
          starts_at: Time.zone.parse("2026-05-24 13:00"),
          ends_at: Time.zone.parse("2026-05-24 15:00"),
          shift: 2.years,
        )

      result = shifter.call

      expect(result[:starts_at]).to eq(Time.zone.parse("2028-05-24 13:00"))
      expect(result[:ends_at]).to eq(Time.zone.parse("2028-05-24 15:00"))
    end

    it "returns a nil ends_at when none was given" do
      shifter = described_class.new(starts_at: Time.zone.parse("2026-05-24 13:00"))

      expect(shifter.call[:ends_at]).to be_nil
    end
  end

  describe ":nth_weekday_of_month strategy" do
    it "preserves the Nth occurrence of the weekday across the shift" do
      # 2026-05-16 is the 3rd Saturday of May 2026; the 3rd Saturday of May
      # 2027 is 2027-05-15 (May 1st 2027 is itself a Saturday).
      shifter =
        described_class.new(
          starts_at: Time.zone.parse("2026-05-16 13:00"),
          strategy: :nth_weekday_of_month,
        )

      expect(shifter.call[:starts_at]).to eq(Time.zone.parse("2027-05-15 13:00"))
    end

    it "falls back to the last occurrence when the target month has fewer of that weekday" do
      # 2024-03-29 is the 5th (last) Friday of March 2024; March 2025 only
      # has 4 Fridays, so the 5th-occurrence math must clamp back to the
      # last Friday (2025-03-28) instead of overflowing into April.
      shifter =
        described_class.new(
          starts_at: Time.zone.parse("2024-03-29 09:00"),
          strategy: :nth_weekday_of_month,
        )

      expect(shifter.call[:starts_at]).to eq(Time.zone.parse("2025-03-28 09:00"))
    end
  end
end
