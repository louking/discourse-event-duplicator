# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseEventDuplicator::DateShifter do
  subject(:shifter) { described_class.new(starts_at: Time.zone.parse("2026-05-24 13:00")) }

  # TODO: once implemented, assert the default shift proposes the same
  # date/time one year later (and that DST/leap-year edges are handled).
  it "is not implemented yet" do
    expect { shifter.call }.to raise_error(NotImplementedError)
  end
end
