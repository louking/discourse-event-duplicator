# Using the Event Duplicator plugin

This is a guide for people *using* the plugin on a Discourse site — what it does, who can use it, and how
the review step works. For the code architecture and development workflow, see the repo's `CLAUDE.md`
instead; this doc doesn't assume you're a developer.

## What it's for

If your community runs recurring calendar events (a race series, a monthly meetup, a season of matches —
anything created with the `discourse-calendar` `[event]` block), you eventually need a new topic for next
year's (or next month's) occurrence. This plugin automates that: it finds the existing event topic(s), works
out a sensible date for the next occurrence, and creates the new topic/event for you — after you've had a
chance to review and adjust the details.

It does **not** touch the original topic. Duplicating creates a brand-new topic with its own `[event]` block;
the source topic is left exactly as it was.

## Who can use it

Two things both have to be true for a given category:

1. You must already be able to create topics in that category (the same permission Discourse uses for
   "can you post here at all").
2. You must belong to one of the groups configured in the **event_duplicator_allowed_groups** site setting.
   By default this is staff only — an admin can add other groups (e.g. a "race organizers" group) to open it
   up further.

If either of those isn't true, you won't see the "Event Duplicator" link in the sidebar or the "Duplicate
event" button on a topic — the controls simply don't appear, rather than showing and then failing.

## Duplicating a whole series

Use this when you have several related event topics — e.g. every race in a season, each tagged
`grand-prix` — and want to roll all of them forward at once.

1. Click **Event Duplicator** in the sidebar.
2. Choose a **category** and one or more **tags**. Topics matching *any* of the selected tags are included
   (so a topic tagged both `grand-prix` and `signature-race` still only shows up once, even if you select
   both tags).
3. Optionally set **"Only events starting after"** / **"...before"** to narrow the search to a specific date
   range — useful if a tag has been used across multiple seasons and you only want this year's races. Leave
   either blank for no limit in that direction; a **Clear** button appears next to a field once it's set.
4. Click **Next**. You'll land on the review page with a proposed next-occurrence date for each matching
   event's topic.

## Duplicating a single topic

Open the topic you want to duplicate, use its admin/wrench menu, and choose **Duplicate event**. This skips
the picker step and takes you straight to the review page for that one topic.

## The review page

Each row is one event topic that will be duplicated if you leave it checked.

- **Topic** — the duplicate's title, pre-filled with the source topic's title. Editable — useful if your
  source titles bake in a date or year (e.g. "Monaco Grand Prix 2026") that you'd want to change rather than
  carry forward unchanged.
- **Old start** — the source event's actual start date, for reference. Read-only.
- **New start** — the proposed start date for the duplicate. Editable — if the proposed date is wrong, just
  change it. Only the calendar date is editable here; the time of day is carried over from the original
  event automatically. There's no separate end-date field: the duplicate's end date is always worked out
  automatically from the source event's own duration (new start + however long the original event ran), so
  it can't end up out of sync with an edited start date.
- **Date TBD** — checked by default, since a shifted date is a *proposal*, not a confirmed one. When
  checked, the duplicate's title and event name get an annotation (`(date TBD)` by default — configurable,
  see below) so it's obviously provisional until someone confirms the real date and unchecks it on a future
  edit. Uncheck it here if you already know the date is correct.
- The checkbox in the first column controls whether that row gets duplicated at all. The checkboxes in the
  header of that column and the Date TBD column select or clear the whole column at once.
- **Date rule** (above the table) controls how the "New start" dates were proposed — see below. Changing it
  recalculates every row's proposed date immediately, unless you've already edited that row's date by hand
  (a manual edit is preserved rather than overwritten by a rule change).

If a topic was already duplicated to the same target year in an earlier run — whether from re-running a
series (this matters if a topic carries more than one series tag and you've run the duplicator once per
tag) or from opening the single-topic "Duplicate event" flow again later — it shows an "Already duplicated
to topic #…" note and starts unchecked, so re-running doesn't accidentally create a second copy. Check the
box yourself if you genuinely want a second copy anyway — checking it back on is treated as deliberate
override and a new duplicate gets created even though one already exists.

Click **Duplicate selected** to create the checked topics. A panel appears below the button once it's done:
a link to each newly created duplicate, and, for anything that couldn't be duplicated, the reason why. This
panel is just page state — it clears if you reload the page, but the topics it linked to aren't affected by
that.

### Date rule

Simply shifting "the same date" forward doesn't always make sense — a lot of recurring events are really
"the 3rd Saturday of the month," not a fixed calendar date. Two rules are available:

| Rule | What it does | Example |
|---|---|---|
| Same calendar date | Adds one year (or whatever the shift is) to the exact date. | July 4, 2026 → July 4, 2027 |
| Same weekday of month | Preserves which occurrence of that weekday it was. | 3rd Saturday of May 2026 → 3rd Saturday of May 2027 |

An admin can set which of these is the site-wide default; you can always override it per run using the
dropdown on the review page.

## Site settings

These are configured under **Admin → Settings**, searching for `event duplicator`:

- **event_duplicator_enabled** — turns the whole plugin on/off.
- **event_duplicator_allowed_groups** — which groups (in addition to having category permission) may use
  the plugin. Default: staff. An **empty** list means *nobody* can use it — to open it to everyone, add the
  "everyone" group rather than clearing the list.
- **event_duplicator_default_date_strategy** — the default date rule (see the table above) used when
  someone hasn't changed the dropdown.
- **event_duplicator_tbd_annotation** — the text appended to a duplicate's title/event name when it's
  flagged "date TBD" (default `" (date TBD)"`). Set it blank to disable the annotation feature entirely.

## Good to know

- Duplicating deliberately reuses the source topic's title — that's the point, it's the same event next
  time around. This intentionally bypasses Discourse's usual "no duplicate topic titles" check for this one
  action, since it's expected/normal here, not a mistake.
- If a duplicate can't be created for some other reason (a genuine validation problem), it shows up in the
  same post-duplication panel as skipped, with the reason why, rather than silently failing or duplicating
  everything else.
- Deleting a duplicate topic frees up its source topic for that occurrence again — the "Already duplicated"
  flag disappears next time you run the duplicator, exactly as if that duplicate had never been created. If
  you undo the deletion (recover the topic from trash), the flag comes right back too, so you can't end up
  with two duplicates for the same occurrence just by deleting-then-recovering one. This only applies to
  topics duplicated after this behavior was added — a duplicate created before then won't free up its source
  if deleted.
