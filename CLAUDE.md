# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Discourse plugin (Ruby on Rails engine + Ember.js admin/user UI) that lets authorized users duplicate
calendar events/topics (created via the `discourse-calendar` plugin) into a new time period — either a
single topic or a whole tagged series (e.g. every topic tagged `grand-prix`), with a review step to edit
proposed dates before committing.

**Status: implemented end to end.** Routes, controller, serializer, service objects, and the backend
duplication pipeline (`DateShifter`, `TopicDeduplicator`, `TopicDuplicator`, `DuplicationTracker`) are
implemented and covered by specs. The frontend has real entry points (a sidebar link + picker page for
series duplication, a topic-admin menu button for single-topic duplication) and the review step supports
editing the proposed start/end date per topic and flagging one as "date TBD" — see the Frontend section
below.

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
npx prettier --check "assets/**/*.{js,gjs,hbs,scss}"
```

`.gjs` formatting/linting needs `prettier-plugin-ember-template-tag` (a devDependency here, wired up in
`.prettierrc.cjs`) — without it, `prettier --check`/`--write` errors with "No parser could be inferred" on
any `.gjs` file rather than silently skipping it.

CI (`.github/workflows/discourse-plugin.yml`) delegates to Discourse's shared `discourse-plugin.yml`
reusable workflow, which runs the Ruby and JS lints above plus `ember-template-lint` on `.hbs` files, *and*
auto-detects and runs this repo's actual test types against a real Discourse core + Postgres + Redis — for
now that's just the RSpec backend suite in `spec/`, since there are no QUnit/system tests yet. This means
every push/PR actually runs `bin/rspec plugins/discourse-event-duplicator/spec` for real, not just lint —
keep specs passing locally before pushing, since CI will now catch what lint alone can't (e.g. wrong
Guardian/Category API usage that only fails at runtime).

**Run `bin/local-ci` before pushing.** It runs the same checks as CI (eslint, rubocop, `zeitwerk:check`,
a dev-mode reload check, and the RSpec suite) against a local Discourse core checkout, in ~20 seconds —
versus several minutes for CI's from-scratch spin-up. It assumes a Discourse core checkout at
`~/discourse` with this plugin symlinked into `plugins/discourse-event-duplicator`; override with the
`DISCOURSE_ROOT` env var if yours lives elsewhere. This is what caught the `guardian.can_create_topic?`
and `routes.append`-vs-`draw` bugs after the fact instead of before — run it first next time.

## Architecture

**Backend (`lib/`, `app/`, `config/`)**
- `plugin.rb` — plugin entry point. Gated by site setting `event_duplicator_enabled`. Registers the
  `event_duplicator_duplications` topic custom field (see `DuplicationTracker` below). On
  `after_initialize`, warns (does not hard-fail) if `discourse-calendar` isn't installed, since this plugin
  depends on its `DiscoursePostEvent::Event` data but doesn't declare a hard gem/plugin dependency.
- `lib/discourse_event_duplicator/engine.rb` — isolated Rails engine (`DiscourseEventDuplicator` namespace),
  autoloads `lib/`.
- `lib/discourse_event_duplicator/date_shifter.rb` — proposes new date(s) for a duplicated event via a
  pluggable `strategy:` (`:calendar_date` default, `:nth_weekday_of_month` — see
  `event_duplicator_default_date_strategy` site setting), each implemented as its own class under
  `DateShifter::Strategies`.
- `lib/discourse_event_duplicator/topic_deduplicator.rb` — given a set of series tags, a guardian, and
  optional category/date-range bounds, returns each matching topic exactly once (even if it carries multiple
  matching tags), scoped to topics that actually have a discourse-calendar event.
- `lib/discourse_event_duplicator/topic_duplicator.rb` — creates the actual duplicate: a new topic whose
  first post contains an `[event ...]` raw block built from the source event's attributes plus the
  confirmed dates, created via `PostCreator` so discourse-calendar's own `on(:post_created)` hook creates the
  `Event` row (see "Key external dependency" below). Passes `skip_validations: true` since a duplicate
  intentionally reuses the source topic's title, which would otherwise trip Discourse's default
  "no duplicate titles" check — this skips that and other generic topic/post content validations (redundant
  for a copy of already-valid, code-generated content) but does *not* skip discourse-calendar's own event
  validation, which is registered as an independent `Post` validation. There's no `ends_at:` parameter; the
  end date is always derived from the source event's own duration
  (`starts_at + (source_event.ends_at - source_event.starts_at)`) via `#effective_ends_at`, so an edited start
  date can't drift out of sync with an independently-edited (and now nonexistent) end date. Accepts `tbd:` —
  race events often don't have a settled date yet, so `tbd: true` appends (and `tbd: false` strips a stale)
  the `event_duplicator_tbd_annotation` site setting's text (default `" (date TBD)"`) on both the new topic's
  title and the event's `name`. Accepts an optional `title:` override (`#effective_title`) — reviewers can
  rename the duplicate rather than always reusing the source topic's title verbatim (e.g. to drop a baked-in
  year); when given, it's used for *both* the new topic's title and, since the two are normally kept in sync,
  the event's own `name` too (still passed through `#annotate`, so `tbd:` layers on top of an override rather
  than being mutually exclusive with it). Falls back to the source topic's title when omitted/blank, which is
  the only behavior before this override existed.
- `lib/discourse_event_duplicator/duplication_tracker.rb` — records, on the *source* topic's
  `event_duplicator_duplications` custom field, which target years it's already been duplicated to. Exists
  because a topic can carry more than one series tag, so two separate tag-scoped runs could otherwise
  duplicate the same event twice; the controller checks this before creating anything and defaults
  already-duplicated items to unselected in the review step (a reviewer can still check that box back on —
  see the `force` param on `#duplicate` below — which is treated as deliberate override).
  Also stamps the *duplicate* topic itself with a reverse-pointer custom field
  (`event_duplicator_source` → `{topic_id, starts_at}` of its source), written alongside the forward record
  in `#record!`. This exists purely so `#forget!`/`#restore!` can find the right source entry in O(1) rather
  than scanning every topic that carries the tracker field: `plugin.rb` hooks `on(:topic_trashed)` /
  `on(:topic_destroyed)` / `on(:topic_recovered)` to call these, so deleting a duplicate topic frees its
  source up for re-duplication again (exactly as if the duplicate had never been created), and recovering it
  re-locks that. Both `on(:topic_trashed)` (the common, reversible delete) and `on(:topic_destroyed)` (fires
  for *that too*, plus a direct staff-only permanent delete that skips trash entirely) call the same
  `#forget!`, which is idempotent, so double-firing on an ordinary trash is harmless — confirmed via Discourse
  core's actual `PostDestroyer`/`Topic` source before picking these events, not assumed; see the request specs
  under "plugin.rb's DiscourseEvent hooks" in `duplication_tracker_spec.rb`, which exercise this through real
  `PostDestroyer` calls rather than firing `DiscourseEvent.trigger` by hand. **Any spec that exercises these
  hooks must `SiteSetting.event_duplicator_enabled = true`** — `Plugin::Instance#on` (not `DiscourseEvent.on`
  directly) silently no-ops every handler when the plugin's `enabled_site_setting` is off, so a spec that
  forgets this will pass for the wrong reason (nothing runs, nothing raises) rather than failing loudly; this
  cost real debugging time before the cause was found. **Known gap:** topics duplicated before this
  reverse-pointer field existed have no way to be traced back to their source, so deleting one of those is a
  silent no-op rather than an error — accepted rather than worth a backfill migration.
- `app/controllers/discourse_event_duplicator/event_duplicator_controller.rb` — the three routes:
  - `GET /event-duplicator/tags/:tag_name/topics` — list deduped topics for series duplication, with
    proposed dates and `already_duplicated` flags attached.
  - `GET /event-duplicator/topics/:topic_id/proposed_dates` — compute the proposed next-occurrence date(s)
    for a single topic, plus (matching `#tagged_topics` above) `already_duplicated`/
    `existing_duplicate_topic_id` from `DuplicationTracker` for that same proposed date. This used to be
    series-only — the single-topic (topic-admin button) review page silently always showed a topic as not
    yet duplicated, even when it had been, until a user noticed the review row for an already-duplicated
    topic wasn't flagged the way the series flow's rows were.
  - `POST /event-duplicator/duplicate` — perform the duplication for `params[:items]` (each with
    `topic_id`, `starts_at`, optional `tbd`/`force`/`title` — no `ends_at`, see `TopicDuplicator` above); each item
    is authorized and checked against `DuplicationTracker` independently (items may span categories), and
    per-item failures (already duplicated, or a remaining Discourse validation failure) are reported back in
    a `skipped` list rather than aborting the whole batch. `force: true` bypasses the `DuplicationTracker`
    skip for that one item — `controllers/event-duplicator.js` on the frontend sends
    `force: item.topic.already_duplicated`, i.e. it's derived from whether the row *arrived* flagged as
    already-duplicated, not from any separate UI control: a reviewer re-checking an already-flagged row's
    (unchecked-by-default) checkbox *is* the override. Before this was wired through, checking that box was
    silently a no-op — the item stayed in the submitted batch but the backend skipped it into `skipped`
    anyway, since `force` was never sent at all. A skipped-as-already-duplicated entry also carries
    `existing_duplicate_topic_url` (`"/t/#{id}"` — Discourse's bare `t/:id` route redirects to the canonical
    slugged URL, so no extra `Topic` lookup is needed just to link to it) alongside
    `existing_duplicate_topic_id`, so the frontend can render an actual link rather than a bare, unusable id.
- `app/serializers/discourse_event_duplicator/duplicatable_topic_serializer.rb` — serializes a topic plus its
  `original_start`/`original_end` and `proposed_start`/`proposed_end` (read straight off
  `object.first_post.event`/`DateShifter`, no extra plumbing needed), `already_duplicated`/
  `existing_duplicate_topic_id`/`existing_duplicate_topic_url` (same `"/t/#{id}"` shape as the `#duplicate`
  action's skipped entries above), and a `selected` default (false when already duplicated). Only
  `original_start`/`proposed_start` are actually shown in the review UI's "Old start"/"New start" columns —
  the `*_end` attributes stay in the API response (harmless, and `#proposed_dates` returns the same fields
  directly for the single-topic case below) but nothing in the frontend reads them anymore, since the
  duplicate's end date is always backend-derived from the source event's own duration rather than
  reviewer-editable; see `TopicDuplicator#effective_ends_at`. Reads the per-topic proposed-date/
  duplicate-tracking data out of the AMS `options` hash (`options.dig(:proposed_dates, object.id)`, not
  `instance_options` — this repo is on `active_model_serializers` 0.8.x, an older API than the
  `instance_options` name suggests). The `#proposed_dates` controller action returns the same
  `original_start`/`original_end`/`already_duplicated`/`existing_duplicate_topic_id`/
  `existing_duplicate_topic_url` fields directly in its JSON (it doesn't go through this serializer, since
  it's a single ad-hoc topic, not a collection) — computed the same way
  (`DuplicationTracker.existing_duplicate_for`), just inlined rather than shared, so any future change to how
  "already duplicated" is determined (or how its link is built) needs updating in both places.
- `app/controllers/discourse_event_duplicator/pages_controller.rb` — serves the plain Discourse SPA shell
  (`raise ::ApplicationController::RenderEmpty`) for `/event-duplicator/new` and `/event-duplicator/review`.
  Required because those are Ember-only client routes: without a real backend action for them, a full page
  load or refresh on either URL 404s instead of booting Ember (see the routing note below).

**Routing — `config/routes.rb` mounts the engine at `"/"`, not at `"/event-duplicator"`, with every route
fully-qualified (`get "/event-duplicator/tags/:tag_name/topics" => ...`) instead.** The Ember UI lives under
that same `/event-duplicator` prefix (`/event-duplicator/new`, `/event-duplicator/review`). A prefix-mounted
engine (`mount Engine, at: "/event-duplicator"`) claims the *entire* path space under that prefix — any
request under it that doesn't match one of the engine's own routes 404s with a real Rails routing error
instead of falling through to Discourse's SPA-shell catch-all, since Rails doesn't retry other top-level
routes once a mount has claimed the prefix. This is why `PagesController` (above) exists too: even with the
mount fixed, the Ember routes still need their own real backend actions to serve the shell on a full page
load. Mirrors the pattern `discourse-calendar` uses in its own `config/routes.rb` for the exact same reason.
**Plugin route files only load at boot** (like `plugin.rb`) — changes here need a `bin/dev` restart, editing
`config/routes.rb` alone does not hot-reload the way editing plugin JS does.

**Authorization model — this is the one thing to get right in any change touching access control:** three
independent checks are AND'd together. A user may duplicate into a category only if **all** of (1)
`guardian.can_create_topic_on_category?(category)` is true (Discourse's own category permissions), (2) the
user belongs to one of the groups in the `event_duplicator_allowed_groups` site setting (a `group_list`
setting, default staff-only — group id `3`), and (3) `guardian.can_create_discourse_post_event?` is true
(discourse-calendar's own gate on who may create `[event]` posts at all, backed by its
`discourse_post_event_allowed_on_groups` site setting). Category permissions alone are *not* sufficient:
bulk-duplicating a whole series is a much heavier action than posting a single topic, so it's gated further
by this plugin-specific allowlist. Note the setting's real semantics: an **empty** list means *nobody*
passes (Discourse's `_allowed_groups` convention), not "unrestricted" — to fully open this up, add the
"everyone" auto-group (id `0`), don't empty the list. Check (3) is deliberately implemented by calling
discourse-calendar's own `Guardian#can_create_discourse_post_event?` (`can_create_calendar_event?` in the
controller) rather than reading `discourse_post_event_allowed_on_groups` directly — this plugin doesn't need
to know discourse-calendar's own config shape, and stays correct if discourse-calendar changes how that
check works; it's guarded with `guardian.respond_to?` so the (non-standard) case of discourse-calendar being
genuinely absent doesn't newly hard-block on a check it can't answer (see the "warn, don't hard-fail" handling
in `plugin.rb`). The frontend's `canDuplicateEvents` mirrors this the same way, reading discourse-calendar's
own serialized `currentUser.can_create_discourse_post_event` rather than reimplementing its group check in
JS. Every controller action must resolve the target category and call `ensure_can_duplicate_into!(category)`
before doing anything else; see the private helpers (`find_category!`, `find_topic!`,
`ensure_can_duplicate_into!`, `can_duplicate_into?`, `can_create_calendar_event?`) in the controller and
follow the same pattern for new actions. `duplicate` re-checks this per item rather than once for the whole
request, since items can span categories.

**Frontend (`assets/javascripts/discourse/`)**
- `lib/can-duplicate-events.js` — `canDuplicateEvents(currentUser, siteSettings)` mirrors the backend's
  group-membership half of `can_duplicate_into?` (intersects `currentUser.groups` against the pipe-separated
  `siteSettings.event_duplicator_allowed_groups`). The category-permission half is handled separately by
  reusing `category.canCreateTopic` / `CategoryChooser`'s default `FULL`-permission filtering, rather than
  reimplementing that check in JS.
- `api-initializers/event-duplicator.js` — `import { apiInitializer } from "discourse/lib/api"` (not
  `discourse/lib/plugin-api`, which no longer exports it), called as `apiInitializer((api) => {...})` with no
  version-string argument — the version-string call form is silently accepted for backwards compatibility
  but the import path isn't, so getting this wrong throws `apiInitializer is not a function` at runtime, not
  a lint/build error. Registers the two entry points, each gated on `canDuplicateEvents` (plus, for the
  topic-admin button, `topic.category.canCreateTopic`) so controls simply don't render for users who couldn't
  use them:
  - `api.addCommunitySectionLink` — a sidebar link to the picker page (series duplication).
  - `api.addTopicAdminMenuButton` — a per-topic button that routes into the review step for that one topic
    (single-topic duplication).
- `routes/event-duplicator-new.js` / `controllers/event-duplicator-new.js` /
  `templates/event-duplicator-new.hbs` — the picker page: category (`<CategoryChooser>`) + multi-tag OR
  select (`<TagChooser>`) + optional, clearable source-event date range (plain `<input type="date">` +
  `{{on "change"}}`, not Ember's `<Input>`, so an empty/cleared value reliably reaches the controller as
  `null` rather than an empty string). Each date field also has an explicit **Clear** `<DButton>`
  (`clearStartsAfter`/`clearStartsBefore`, shown only `{{#if}}` that field is set) rather than relying on the
  reviewer to clear the native input by hand: Chrome's segmented mm/dd/yyyy editing only clears whichever
  segment currently has keyboard focus when backspacing, not the other segments, so a user backspacing
  through the field is often left looking at stale leftover digits in the untouched segments even though
  `input.value` has already gone empty (confirmed live — `.value` reads `""` immediately, but the visible
  text doesn't reset until something else assigns the property directly, e.g. the native browser "×" icon,
  Chrome-only and easy to miss, or programmatically). The Clear button sets the tracked property to `null`
  directly, which re-binds the input's `value` property as a whole and does properly reset every segment.
  Then, transitions into the review route with those as query params.
  `beforeModel` redirects away if `canDuplicateEvents` fails, as defense in depth for direct URL navigation
  (the sidebar link already hides the entry point). **`<TagChooser>`'s `@onChange` hands back full tag
  objects (`{id, name, slug, ...}`), not plain name strings** — despite `valueProperty: "id"` in its
  `@selectKitOptions`, confirmed empirically (a static read of `select-kit.js` suggested otherwise). Always
  normalize with `tag.name` in the handler; a naive `.join(",")` on the raw array produces the literal string
  `"[object Object]"` sent to the backend, with no error anywhere in the pipeline.
- `services/event-duplicator.js` — thin `ajax()` wrappers around the three backend routes; this is the only
  place JS talks to the API. `taggedTopics` takes `{ categoryId, tags, startsAfter, startsBefore,
  dateStrategy }`; `tags[0]` becomes the `:tag_name` path segment and the rest become `additional_tags` (OR).
  **`duplicate` must send its body as explicit JSON** (`contentType: "application/json"` +
  `data: JSON.stringify({ items })`), confirmed live as an actual bug when this used plain `data: { items }`
  instead: `ajax()` is a thin `$.ajax` wrapper with no default `contentType`, so jQuery fell back to
  form-urlencoded, which serializes an array of objects as indexed bracket params (`items[0][topic_id]=...`).
  Rails parses that shape into a `Hash` keyed by the string `"0"`, not an `Array` — so the controller's
  `Array(params[:items])` wrapped the *whole* hash as a single bogus item rather than decomposing it,
  `item[:topic_id]` read back as `nil`, and every duplication 404'd via `Discourse::NotFound`. The request
  spec for `#duplicate` never caught this because it posts `items:` through Rails' own test `post` helper,
  which builds a real Ruby Array directly — it never exercises jQuery's client-side serialization at all.
  Any future POST/PUT here that sends an array of objects (not just flat scalars) needs the same explicit
  JSON treatment; see `Topic.update`/`.bulkOperation` in Discourse core's `discourse/models/topic.js` for the
  established pattern.
- `routes/event-duplicator.js` / `event-duplicator-route-map.js` — route `/event-duplicator/review`, driven
  entirely by query params (`topic_id` for single-topic mode, or `category_id`/`tags`/`starts_after`/
  `starts_before`/`date_strategy` for series mode) rather than a dynamic segment, so both entry points share
  one route/review UI. Resolves `date_strategy` to `params.date_strategy || siteSettings.event_duplicator_default_date_strategy`
  and passes the resolved value through as `model.dateStrategy`, both to actually use it and so the review
  page's date-rule `<select>` has a real value to show/default to. `modelForSingleTopic` maps
  `already_duplicated`/`existing_duplicate_topic_id`/`selected` straight off the `proposed_dates` response
  (see the controller action above) rather than hardcoding `already_duplicated: false` — an earlier version
  of this route did hardcode it, since single-topic mode was added before series mode's dedup-flagging was;
  that meant the review row for an already-duplicated topic looked identical to a fresh one right up until
  clicking "Duplicate selected", when the backend would silently skip it anyway (see `#duplicate`'s
  per-item `skipped` handling). Fixed once the confirmation-result panel below made that silent skip visible
  enough for a user to notice and ask why the row wasn't flagged like the series flow's rows are.
- `controllers/event-duplicator.js` — holds `isDuplicating` state, `confirmDuplication` (maps selected review
  items to `{ topic_id, starts_at, tbd, title }` before calling the service — no `ends_at`; see
  `TopicDuplicator` on the backend), and `setDateStrategy` (a `<select>` change handler that `transitionTo`s
  with a new `date_strategy` query param — the route's `queryParams` config has `refreshModel: true` for it,
  so this alone re-runs `model()` with the new strategy and recomputes every row's proposed dates).
  `confirmDuplication` stores the `duplicate()` response on `@tracked result` (`{ duplicated, skipped }`, each
  entry joined with a `title` looked up from the submitted items, since the backend response itself only
  carries topic ids) — `EventDuplicatorReview` reads `result.duplicated` itself (passed down as `@result`) to
  mark each successfully-duplicated row directly in the review table (see below), rather than this listing
  them in a separate panel. `templates/event-duplicator.hbs` only renders a panel below the table for
  `result.skipped` (genuine failures/edge-case skips), with a link-style "duplicated to topic" message for
  ones skipped as already-duplicated, reusing the same locale string
  (`event_duplicator.review.duplicated_to_topic`) and `existing_duplicate_topic_url` the review table's own
  annotation uses. There used to also be a "Duplicated:" success list here (and confirming used to `await` the
  response and discard it entirely before that, so clicking "Duplicate selected" gave no feedback at all) —
  both replaced once a user asked for the in-row link/disabled-checkbox treatment instead, since a separate
  bottom panel meant a duplicated row and a still-pending one looked identical in the table above it.
  `confirmDuplication` accumulates `result.duplicated` across multiple submissions (`previouslyDuplicated`,
  captured *before* the new request lands, since `result` is no longer nulled at the start of a submission —
  doing so caused already-duplicated rows to flash back to their enabled state for the request's duration)
  rather than replacing it — necessary because `EventDuplicatorReview#confirm` excludes already-duplicated
  rows from the next submission's payload entirely (see below), so if a reviewer retries a batch that
  partially failed, the earlier response's `duplicated` entries would otherwise never reappear in a later
  response and the rows would silently lose their link/disabled state. `result.skipped` is *not* accumulated
  the same way — each submission's skip list simply replaces the last one, since stale skip reasons from an
  earlier attempt aren't useful once retried. `result` is plain in-memory controller state, not persisted
  anywhere (not a query param, not localStorage) — a hard page reload re-instantiates the controller and
  re-runs `model()`, which clears it back to `null`, losing the disabled/link row state along with it; this is
  deliberate (same as any flash-style confirmation) rather than a bug, since the underlying duplicate topic
  itself isn't lost, only this session's confirmation state.
- `components/event-duplicator-review.gjs` — the review/edit step: an editable **Topic** title (pre-filled
  from `topic.title`, plain `<input type="text">`) alongside the start date (**Old start**, read-only, from
  `topic.original_start`; **New start**, editable) — there's no end-date column, since the backend always
  derives the duplicate's end date from the source event's own duration (see
  `TopicDuplicator#effective_ends_at`). The New start input is an `<input type="date">` (day granularity
  only, per product decision — race event times don't change, just sometimes the date); editing it
  reconstructs the full ISO string by splicing the new date onto the *existing* time-of-day
  (`dateOnly`/`withNewDate` helpers) rather than losing the time or requiring a separate time input. **Per-topic
  state is split into `@topics` (the proposal) and a separate `edits` Map (topic id → only the fields the user
  has actually touched, currently `isSelected`/`tbd`/`startsAt`/`title`)** — deliberately *not* a single
  `@tracked` field seeded from `@topics` at construction
  time. That was tried first and was the actual cause of "changing the date rule has no effect": a Glimmer
  class field initializer runs once, when the component is constructed, and does not rerun when `@args`
  change later — so a `@tracked itemStates = new Map(this.args.topics.map(...))` field keeps showing the
  *first* proposed dates forever, even though `model()` recomputes a fresh `@topics` array (with new
  `proposed_start` values) every time the reviewer picks a different date rule. The `items` getter now
  recomputes from `@topics` on every access, falling back to each topic's live `proposed_start` unless the
  user has an entry in `edits` for that field; `edits` itself is a plain (non-tracked) `Map`, with a
  `@tracked revision` counter bumped after every mutation so the getter (which reads `revision`) knows to
  rerun. Header checkboxes in the selection and Date TBD columns select/clear that whole column
  (`allSelected`/`allTbd` getters, `toggleAllSelected`/`toggleAllTbd` actions) rather than only per-row.
  `isSelected` defaults from each topic's `selected` flag from the backend — false for topics
  `DuplicationTracker` already flagged as duplicated. Also accepts `@result` (the controller's
  `{ duplicated, skipped }` state, see above) purely to compute `justDuplicated`/`duplicateUrl` per row —
  `duplicatedUrlByTopicId` is a `Map` built fresh from `@result.duplicated` on every `items` access (topic id
  → `new_topic_url`), and a row whose topic id is in that map renders the same "duplicated to topic" link
  used for a topic that arrived *already* duplicated (`item.topic.already_duplicated`, checked first since
  it's the more current of the two), and has its selection checkbox `disabled`. `confirm()` additionally
  filters out any `justDuplicated` row even if `isSelected` is still (necessarily) `true` on it — the checkbox
  being disabled only stops the reviewer from *un*checking it by hand, it doesn't stop `items` from still
  reporting it selected, so without this explicit filter a later "Duplicate selected" click (e.g. retrying
  other rows that failed) would silently resubmit and re-duplicate an already-completed row. **Single-file
  `.gjs` (class + colocated `<template>`),
  not a separate `.js` + `.hbs` pair** —
  this plugin's dev-mode JS pipeline (rolldown-based, distinct from the classic Ember CLI build) does not
  support the classic "same-named `.hbs` next to the `.js` in `components/`" colocation convention some
  guides describe as the fix for the `component-template-resolving` deprecation; that arrangement compiled
  without error here but the component silently rendered nothing. `.gjs` with an inline `<template>` is the
  form that actually works. The two top-level route templates (`templates/event-duplicator.hbs`,
  `templates/event-duplicator-new.hbs`) are still classic `.hbs` and log a (non-blocking) `.hbs` extension
  deprecation warning on boot — only worth converting to `.gjs` if that warning becomes an enforced error.

## Key external dependency

`discourse-calendar` owns event data via **`DiscoursePostEvent::Event`** (`original_starts_at`,
`original_ends_at`, `timezone`, `all_day`, `recurrence*`, accessible off a post as `post.event`) — *not* via
the `TopicEventStartsAt`/`TopicEventEndsAt`/`TopicEventAllDay` topic custom fields, which are read-only
display mirrors auto-derived from the real event and would desync if written directly. Events are normally
created/updated by parsing an `[event ...]` markdown block out of a post's raw text
(`DiscoursePostEvent::Event::SyncFromPost`, triggered on `on(:post_created)`/`on(:post_edited)`). This
plugin's `TopicDuplicator` goes through that same path — building a new post's raw with an `[event]` block —
rather than writing `DiscoursePostEvent::Event` rows directly, so discourse-calendar's own validations,
invitee handling, and custom-field sync all apply. Any new date-shifting or event-creation logic must follow
this same path rather than inventing plugin-local date storage or touching discourse-calendar's tables
directly.
