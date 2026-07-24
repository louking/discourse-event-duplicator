# discourse-event-duplicator

A [Discourse](https://www.discourse.org/) plugin that lets authorized users duplicate calendar events/topics
(created via [discourse-calendar](https://github.com/discourse/discourse-calendar)) into a new time period.

## Status

Early skeleton — routes, controller, and Ember UI are wired up end to end but the actual duplication logic
(deduping, date-shifting, topic/event creation) is not implemented yet.

## What it does (planned)

- **Series duplication**: pick a tag (e.g. `grand-prix`, `signature-race`), list every topic tagged with it
  (or any of a set of tags, deduped so multi-tagged topics only show up once), propose next-occurrence dates
  for each, let the user review/edit dates and uncheck any they don't want, then create the new topics/events.
- **Single event duplication**: the same review-and-confirm flow for one topic at a time.

## Requirements

- [discourse-calendar](https://github.com/discourse/discourse-calendar) must be installed and enabled — this
  plugin reads and writes the topic/post custom fields it defines for event dates.
- Events being duplicated live in a specific category. There is no plugin-specific group or role: a user may
  duplicate into that category if and only if they already have permission to create topics there
  (`guardian.can_create_topic_on_category?(category)`). Category permissions are the only authorization boundary.

## Installation

Add to your `containers/app.yml` (or clone into `plugins/` for local development) as with any other Discourse
plugin. See the [Discourse plugin installation guide](https://meta.discourse.org/t/install-a-plugin/19157).

## Development

```bash
# from a discourse core checkout, with this repo cloned into plugins/discourse-event-duplicator
bin/rspec plugins/discourse-event-duplicator/spec
yarn eslint plugins/discourse-event-duplicator/assets/javascripts
bundle exec rubocop plugins/discourse-event-duplicator
```

## License

Apache-2.0, see [LICENSE](LICENSE).
