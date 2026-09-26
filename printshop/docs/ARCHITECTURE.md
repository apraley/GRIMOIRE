# PRINT SHOP architecture

## Layers

```
screens/      UI: one table per screen, pushed on a stack (components/screens_mgr.lua)
components/   house-style drawing, pixel text, input, widgets, form, sprites
services/     domain logic; the only code that mutates Store.data
providers/    printer adapters behind PrinterProvider
models/       record shapes, normalizers, schema + migrations
data/         static content: font, seed shop, procedures, phrases
lib/          pure helpers: util, clock, rng, events
```

Rules of thumb:

* Screens read through services and never write records directly. The
  editors are the exception: they copy a draft and write it back on SAVE.
* Services announce what happened on the event bus (`lib/events.lua`).
  Other services and the app react to it. This keeps the tools linked
  without circular imports.
* Models hold no references to live objects, so everything in
  `Store.data` survives a JSON round trip.

## Event flow

| Event | Emitted by | Consumed by |
|---|---|---|
| `print.started` | Printing.start | (hooks) |
| `print.finished` | Printing.finish | Captain inbox, toasts and sounds |
| `print.error` | provider `failed` event | failure log is opened, toast |
| `print.runout` | provider `runout` event | toast; Watch offers SWAP SPOOL |
| `printer.state` | provider `state` event | (hooks) |
| `spool.low` / `spool.damp` | Filament | Captain inbox, toast |
| `maint.due` / `maint.done` | MaintService | Captain inbox, toast |
| `calib.saved` | CalService | Captain inbox |
| `job.added` / `job.retry` | Queue | Captain inbox (retry) |

## The finish transaction

`Printing.finish(job, outcome, details)` is the only path that records a
finished attempt. It is used by provider completion, resolved failure logs
and manual MARK COMPLETE / MARK FAILED:

1. `Filament.consume(spool, grams - preConsumed)`. `preConsumed` covers
   grams already taken off an emptied spool during a runout swap, so
   nothing is counted twice.
2. Spool success/failure counters. The first successful temps become the
   spool's favourites if it has none.
3. A `History` record, which carries the failure cause.
4. Printer stats and the hour odometer. `MaintService.checkCrossings`
   compares each task's due state before and after, and emits `maint.due`.
5. Job status and dates.
6. `print.finished` and an immediate save.

Printer-reported failures are held in `Store.data.pendingFailure` (saved,
so it survives a restart) until the user logs a cause. While one is
pending, new jobs can't start, so every failure gets a real cause.

## Persistence

`services/store.lua` loads, migrates, repairs and debounces saves.
`models/schema.lua` holds:

* `Schema.migrations[v]`: pure functions from v-1 to v. Each is written to
  tolerate half-migrated input.
* `Schema.repair(doc)`: runs after every load. It normalizes each record
  (types, enums, ranges), reserves ids above the highest existing one,
  replaces duplicate ids, clears dangling references and makes sure there
  is at least one printer.

Live printer state (the provider's progress and temperatures) changes all
the time during a print. It is written every 30 seconds to a small side
file, `printshop-live`, so the main document (hundreds of history and
ledger rows) isn't re-encoded and rewritten mid-print. The main save still
carries a copy. On load, whichever copy is newer wins.

JSON caveats handled: lists are always dense arrays (`U.asList` rebuilds
them), maps use string keys (calibration keys look like `p1|PLA|BAMBU`),
nothing stored is a function or NaN, and ledgers and logs are capped so the
file can't grow without bound.

Numbers: dates are integer seconds since 2000-01-01 (the Playdate epoch),
and date math uses integer division. The RNG keeps every product below
2^31, so it behaves the same on any Lua number configuration.

## Providers

The demo simulator works in simulated seconds: real time multiplied by
`settings.demoSpeed`. `DemoProvider:step(sec)` handles any step size
analytically, jumping to the next milestone (temps reached, failure point,
runout point, completion). That keeps the fast-forward cheap when the app
was closed for hours. Whether an attempt fails is decided up front in
`planOutcome` from the spool's dryness and track record, calibration
coverage, material, and overdue maintenance. It is seeded by job id and
attempt number, so it is deterministic.

The bridge providers poll every 3s, back off up to 8x while offline, have
one request in flight at a time with a timeout, and create HTTP
connections only from the update loop (the SDK's permission prompt yields
a coroutine).

## The Benchy Captain

`services/captain.lua` + `data/phrases.lua`:

1. **Inbox.** Event handlers turn domain events into prioritized news
   items. The inbox is saved and capped at 8.
2. **Rules.** `Captain.candidates()` scores topics from live state:
   suggestions derived from failures (`Stats.suggestions`, which drops
   anything already fixed by a newer calibration run or maintenance log),
   due chores, low or damp spools, filament shortfalls for the next job,
   missing profiles, idle printer, queue status, stats, favourite combo,
   wisdom. Topics used recently are down-weighted.
3. **Composition.** OPENER (mood-aware) + BODY (topic bank with `{slots}`)
   + CLOSER. The RNG is seeded by topic, day and conversation counter, so
   the same shop on the same day is reproducible and asking again moves the
   conversation on. The banks give over 10,000 combinations (the tests
   check this).

## Rendering and performance

* The display is set to 30 fps, and every screen redraws each frame in
  immediate mode (no sprites).
* Text uses a custom 5x9 font. Glyphs are built into images at startup,
  and whole strings are cached as images in two generations of up to 260
  each, so strings still on screen survive a cache rollover. A line of
  text costs one `image:draw` per frame, with no closure or table
  allocated. Typewriter text draws the in-progress line glyph by glyph.
  Wrapped paragraphs and formatted dates are cached as well.
* The layer visualizer caches its image by (shape, size, printed rows).
* Dither patterns are fixed 8x8 `setPattern` tables. They are the only
  greys used.
* Heavier aggregates (Stats over history) are only computed on screens
  that show them. They are memoized on the store revision (`lib/memo.lua`),
  and history is capped at 500 records.
* Per-frame garbage is kept low: `Printing.snapshot()` is cached until the
  next provider drain or data change, `pollEvents()` returns a shared empty
  list when nothing happened, and the demo AMS slots are cached.

## Adding things

* **A printer family:** a new provider in `providers/`, registered in
  `PROVIDER_CLASSES` (services/printing.lua) and `Enums.PROVIDERS`.
* **A calibration procedure:** append to `CalibDefs.list`. The wizard
  screen handles the step types `info`, `check`, `dial`, `measure`, `pick`
  and `summary`.
* **Captain lines:** add to a topic bank in `data/phrases.lua`. Use only
  slots the matching rule provides; a test catches any unfilled slot.
* **A schema change:** bump `Schema.CURRENT`, add a migration and a repair
  step, and extend the v1 fixture test.
