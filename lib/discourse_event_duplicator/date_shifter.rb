# frozen_string_literal: true

module ::DiscourseEventDuplicator
  # Proposes new date(s) for a duplicated event, given its current
  # discourse-calendar start/end. Defaults to shifting forward by one year,
  # landing on the same calendar date -- but recurring series defined by
  # weekday (e.g. "3rd Saturday of the month", "last Friday of the month")
  # need a different landing rule, hence the pluggable `strategy:`.
  class DateShifter
    module Strategies
      # date + shift, e.g. July 4th -> July 4th next year.
      class CalendarDate
        def call(date, shift)
          date + shift
        end
      end

      # Preserves "the Nth <weekday> of the month" across the shift, e.g. the
      # 3rd Saturday of May -> the 3rd Saturday of May next year. If the
      # target month doesn't have an Nth occurrence (5th Monday, say), falls
      # back to the last occurrence in that month rather than overflowing
      # into the next month.
      class NthWeekdayOfMonth
        def call(date, shift)
          target_anchor = date + shift
          weekday = date.wday
          occurrence = ((date.day - 1) / 7) + 1

          first_of_month = Date.civil(target_anchor.year, target_anchor.month, 1)
          first_occurrence = first_of_month + ((weekday - first_of_month.wday) % 7)
          target_date = first_occurrence + (occurrence - 1) * 7
          target_date -= 7 if target_date.month != target_anchor.month

          date.change(year: target_date.year, month: target_date.month, day: target_date.day)
        end
      end
    end

    STRATEGIES = {
      calendar_date: Strategies::CalendarDate.new,
      nth_weekday_of_month: Strategies::NthWeekdayOfMonth.new,
    }.freeze

    def initialize(starts_at:, ends_at: nil, shift: 1.year, strategy: :calendar_date)
      @starts_at = starts_at
      @ends_at = ends_at
      @shift = shift
      @strategy = STRATEGIES.fetch(strategy.to_sym)
    end

    def call
      {
        starts_at: @strategy.call(@starts_at, @shift),
        ends_at: @ends_at && @strategy.call(@ends_at, @shift),
      }
    end
  end
end
