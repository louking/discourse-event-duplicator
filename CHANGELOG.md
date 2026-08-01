# Changelog

All notable changes to this plugin are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [1.1.0] - 2026-08-01

### Added

- Configurable month-based date shift: a "Shift (months)" field on the review
  page controls how many months forward a duplicated event's date is moved
  (12 for annual, 3 for quarterly, etc.), with a site-wide default via the new
  `event_duplicator_default_shift_months` site setting (#19).

## [1.0.1] - 2026-07-28

### Fixed

- Review page: widened the Date rule dropdown so the "Same weekday of month"
  option text no longer clips, capped the Topic title input's width so one
  unusually long title doesn't stretch the whole column, and added a spinner
  to the Duplicate selected button while a duplication is in progress (#18).

## [1.0.0] - 2026-07-27

First stable release. Backend, frontend, and automated test coverage
(RSpec + QUnit) are all in place.

### Added

- Duplicate a single calendar event/topic into a new date via a topic-admin
  menu button, or duplicate a whole tagged series (e.g. every topic tagged
  `grand-prix`) via a sidebar picker page.
- Review step for editing the proposed start date and title per topic before
  committing, with an option to flag a topic's date as "TBD" (configurable
  annotation text via the `event_duplicator_tbd_annotation` site setting).
- Two pluggable date-shifting strategies — same calendar date next year, or
  Nth weekday of month — selectable per run, with a configurable default via
  `event_duplicator_default_date_strategy`.
- Duplicate tracking to prevent re-duplicating the same event twice when a
  topic carries more than one series tag; already-duplicated topics are
  flagged and unselected by default in review, with an explicit override to
  force a re-duplication. Deleting a duplicate topic automatically frees its
  source for re-duplication.
- Post-duplication confirmation: successfully duplicated rows link to their
  new topic and are disabled from resubmission; failures are reported
  per-item without aborting the rest of the batch.
- Authorization gated on category permissions, an
  `event_duplicator_allowed_groups` site setting, and discourse-calendar's
  own event-creation permission.

[Unreleased]: https://github.com/louking/discourse-event-duplicator/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/louking/discourse-event-duplicator/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/louking/discourse-event-duplicator/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/louking/discourse-event-duplicator/releases/tag/v1.0.0
