# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseEventDuplicator::TopicDeduplicator do
  subject(:deduplicator) { described_class.new(tags: tags) }

  let(:tags) { %w[grand-prix signature-race] }

  # TODO: once implemented, assert that a topic tagged with both
  # "grand-prix" and "signature-race" is only returned once.
  it "is not implemented yet" do
    expect { deduplicator.call }.to raise_error(NotImplementedError)
  end
end
