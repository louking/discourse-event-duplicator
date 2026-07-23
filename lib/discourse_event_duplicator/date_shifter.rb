# frozen_string_literal: true

module ::DiscourseEventDuplicator
  # Proposes new date(s) for a duplicated event, given its current
  # discourse-calendar start/end. Defaults to shifting forward by one year.
  class DateShifter
    def initialize(starts_at:, ends_at: nil, shift: 1.year)
      @starts_at = starts_at
      @ends_at = ends_at
      @shift = shift
    end

    def call
      raise NotImplementedError, "DateShifter#call is not implemented yet"
    end
  end
end
