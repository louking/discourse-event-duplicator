# Changelog

All notable changes to this plugin are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

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

[Unreleased]: https://github.com/louking/discourse-event-duplicator/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/louking/discourse-event-duplicator/releases/tag/v1.0.0
