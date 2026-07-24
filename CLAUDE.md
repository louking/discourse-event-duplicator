# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Discourse plugin (Ruby on Rails engine + Ember.js admin/user UI) that lets authorized users duplicate
calendar events/topics (created via the `discourse-calendar` plugin) into a new time period — either a
single topic or a whole tagged series (e.g. every topic tagged `grand-prix`), with a review step to edit
proposed dates before committing.

**Status: early skeleton.** Routes, controller, serializer, service objects, and the Ember route/controller/
component are wired up end to end, but the core logic is unimplemented — `DateShifter#call` and
`TopicDeduplicator#call` both `raise NotImplementedError`, and the controller actions have `# TODO` bodies
returning empty/nil results. Tests currently assert the not-implemented behavior. When implementing a piece,
update its spec to test real behavior instead of the `NotImplementedError` placeholder.

This repo is meant to be developed as a plugin cloned into a Discourse core checkout's `plugins/` directory
(it is not runnable standalone).

## Commands

Run from a Discourse core checkout with this repo in `plugins/discourse-event-duplicator`:

```bash
bin/rspec plugins/discourse-event-duplicator/spec                                    # full spec suite
bin/rspec plugins/discourse-event-duplicator/spec/lib/discourse_event_duplicator/date_shifter_spec.rb  # single file
bin/rspec plugins/discourse-event-duplicator/spec/path/to/spec.rb:LINE                # single example
bundle exec rubocop plugins/discourse-event-duplicator                                # Ruby lint (rubocop-discourse rules)
```

From this repo's own directory (JS tooling is self-contained via `package.json`):

```bash
yarn eslint assets/javascripts        # or: npm run lint
```

CI (`.github/workflows/discourse-plugin.yml`) delegates to Discourse's shared `discourse-plugin.yml`
reusable workflow, which runs the Ruby and JS lints above plus `ember-template-lint` on `.hbs` files, *and*
auto-detects and runs this repo's actual test types against a real Discourse core + Postgres + Redis — for
now that's just the RSpec backend suite in `spec/`, since there are no QUnit/system tests yet. This means
every push/PR actually runs `bin/rspec plugins/discourse-event-duplicator/spec` for real, not just lint —
keep specs passing locally before pushing, since CI will now catch what lint alone can't (e.g. wrong
Guardian/Category API usage that only fails at runtime).

## Architecture

**Backend (`lib/`, `app/`, `config/`)**
- `plugin.rb` — plugin entry point. Gated by site setting `event_duplicator_enabled`. On `after_initialize`,
  warns (does not hard-fail) if `discourse-calendar` isn't installed, since this plugin depends on its
  topic/post custom fields for event start/end dates but doesn't declare a hard gem/plugin dependency.
- `lib/discourse_event_duplicator/engine.rb` — isolated Rails engine (`DiscourseEventDuplicator` namespace),
  autoloads `lib/`.
- `lib/discourse_event_duplicator/date_shifter.rb` — proposes new date(s) for a duplicated event (default:
  shift forward 1 year). Not yet implemented.
- `lib/discourse_event_duplicator/topic_deduplicator.rb` — given a set of series tags, returns each matching
  topic exactly once even if it carries multiple matching tags. Not yet implemented.
- `app/controllers/discourse_event_duplicator/event_duplicator_controller.rb` — the three routes:
  - `GET /event-duplicator/tags/:tag_name/topics` — list deduped topics for series duplication.
  - `GET /event-duplicator/topics/:topic_id/proposed_dates` — compute proposed next-occurrence date(s).
  - `POST /event-duplicator/duplicate` — perform the duplication for the reviewed/confirmed item set.
- `app/serializers/discourse_event_duplicator/duplicatable_topic_serializer.rb` — serializes a topic plus its
  proposed dates and default `selected` state for the review UI.

**Authorization model — this is the one thing to get right in any change touching access control:** there is
no plugin-specific group or role. A user may duplicate into a category if and only if
`guardian.can_create_topic_on_category?(category)` is true for that category — i.e. Discourse's own category permissions
are the *entire* authorization boundary. Every controller action must resolve the target category and call
`ensure_can_duplicate_into!(category)` before doing anything else; see the existing private helpers
(`find_category!`, `find_topic!`, `ensure_can_duplicate_into!`) in the controller and follow the same pattern
for new actions.

**Frontend (`assets/javascripts/discourse/`)**
- `api-initializers/event-duplicator.js` — plugin API entry point. Placeholder: real UI entry point (a button
  on tag pages via `api.decorateTagPage`/`addTagsHtmlCallback`, and/or a topic-admin menu item) is not yet
  decided. Any entry point added here must gate rendering on the same permission check the backend enforces,
  so controls simply don't appear for users who couldn't use them.
- `services/event-duplicator.js` — thin `ajax()` wrappers around the three backend routes; this is the only
  place JS talks to the API.
- `routes/event-duplicator.js` / `event-duplicator-route-map.js` — route `/event-duplicator/:tag_name`, model
  hook loads tagged topics via the service.
- `controllers/event-duplicator.js` — holds `isDuplicating` state and the `confirmDuplication` action that
  calls the service.
- `components/event-duplicator-review.js` (+ `.hbs`) — the review/edit step: per-topic checkbox selection
  state (`Map` of topic id → boolean) plus a `confirm` action that filters to selected items and calls
  `onConfirm`.

## Key external dependency

`discourse-calendar` owns the topic/post custom fields this plugin reads (existing event dates) and will
write (new duplicated event dates). Any date-shifting or event-creation logic must go through those custom
fields rather than inventing plugin-local date storage.
