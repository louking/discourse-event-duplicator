# discourse-event-duplicator

A [Discourse](https://www.discourse.org/) plugin that lets authorized users duplicate calendar events/topics
(created via [discourse-calendar](https://github.com/discourse/discourse-calendar)) into a new time period.

## Status

Implemented end to end. Series and single-topic duplication both work, with a review step for editing
proposed dates, choosing a date-shift rule, and flagging events as not-yet-settled. See
[docs/USAGE.md](docs/USAGE.md) for a full walkthrough of what it does and how to use it. This README stays
high-level.

## What it does

- **Series duplication**: pick a category and one or more tags (e.g. `grand-prix`, `signature-race`; any
  match counts, deduped so multi-tagged topics only show up once), optionally restrict to events in a date
  range, then review proposed next-occurrence dates (with a choice of date-shift rule) before confirming.
- **Single event duplication**: the same review-and-confirm flow for one topic at a time, from that topic's
  admin menu.
- A review step showing each event's original start date alongside an editable proposed new one, plus a
  "date TBD" flag for events whose real-world date isn't settled yet. The end date is always derived
  automatically from the source event's own duration.

## Requirements

- [discourse-calendar](https://github.com/discourse/discourse-calendar) must be installed and enabled. This
  plugin duplicates events by going through discourse-calendar's own `[event ...]` post markup and
  `DiscoursePostEvent::Event` model, not by inventing separate date storage.
- Category permissions are necessary but not sufficient for authorization: a user must both have permission
  to create topics in the target category *and* belong to one of the groups in the
  `event_duplicator_allowed_groups` site setting (default: staff only). See
  [docs/USAGE.md](docs/USAGE.md#site-settings) for the full settings reference.
- Tested against Discourse 2026.7.0. Not verified on earlier releases.

## Installation

Add to your `containers/app.yml` (or clone into `plugins/` for local development) as with any other Discourse
plugin. See the [Discourse plugin installation guide](https://meta.discourse.org/t/install-a-plugin/19157).

## Development

```bash
# from a discourse core checkout, with this repo cloned/symlinked into plugins/discourse-event-duplicator
bin/rspec plugins/discourse-event-duplicator/spec
bundle exec rubocop plugins/discourse-event-duplicator
bin/rake plugin:qunit[discourse-event-duplicator]

# from this repo's own directory (JS tooling is self-contained via package.json)
yarn eslint assets/javascripts test/javascripts
npx prettier --check "assets/**/*.{js,gjs,hbs,scss}" "test/**/*.{js,gjs}"
```

### Running all checks before pushing

CI runs eslint, rubocop, a `zeitwerk:check`, a Rails dev-mode reload check, the RSpec suite, and the QUnit
suite against a real Discourse core checkout, but that spins up a fresh environment from scratch and takes
several minutes. To run the same checks locally in seconds against a Discourse core checkout you already
have set up:

```bash
bin/local-ci
```

By default it looks for a Discourse core checkout at `~/discourse` with this plugin symlinked into
`plugins/discourse-event-duplicator`. If yours lives somewhere else:

```bash
DISCOURSE_ROOT=/path/to/discourse bin/local-ci
```

It doesn't run the QUnit suite yet (that needs a Chrome-on-`PATH`/sandbox setup that's more
environment-specific than the other checks). Run `bin/rake plugin:qunit[discourse-event-duplicator]`
separately before pushing a frontend change.

Run this before every push. It's what would have caught a couple of real bugs (a wrong Guardian method
name, a route-mounting pattern that broke on reload) before they ever reached CI.

## License

Apache-2.0, see [LICENSE](LICENSE).
