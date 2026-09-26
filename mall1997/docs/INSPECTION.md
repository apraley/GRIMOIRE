# 30-day simulation inspection

After the first complete build I generated a mall and ran it for 30 in-game days
with no player input. I did this several times, with and without the autopilot
player (`tools/bot.lua`), using `tools/sim30.lua`. Each run prints a report on
every system, and I read it to answer one question per system: does it create
meaningful change over a month?

```
lua5.4 tools/sim30.lua <seed> <days> [--bot]
TIMELINE_OUT=timeline.txt lua5.4 tools/sim30.lua 1997 30 --bot
```

The current output for seed 1997 is saved in `docs/sim30_report.txt` and
`docs/sim30_timeline.txt`.

## What the first runs showed, and what I changed

| System | Symptom in the first 30-day runs | Fix |
|---|---|---|
| **Store economics** | No store ever got into trouble: every store's cash rose all month and there were 0 closures. When rents were first tightened, the opposite happened: only 24 of 137 stores turned a profit. Stock drained to 0 at the busiest stores (department stores, the cinema, food), so revenue collapsed. | Stock is now restocked daily from what sold, with the restock paid through cost of goods. It only runs down when a store is broke and suppliers stop extending credit. Each store has a persistent quality `q` that sets the popularity it drifts toward. Rent is calibrated per store against expected revenue at average popularity, using the real weekly footfall mix (4,500/day, not 5,600). Starting cash reflects how well each store has been run. Result: about half the stores gain and half lose, roughly 22–28 are in trouble, and weak stores run sales, change managers and eventually close. Closing announcements are capped per week and spaced by each owner's patience. |
| **Relationships** | Friendships only ever increased (+527 / −3 friend edges in a month). A couple could break up with *itself* ("Amanda Lutz and Amanda Lutz broke up"). Adults started dating at a noisy rate. | Weekly decay toward neutral, and cold acquaintances are forgotten. The breakup pairing bug is fixed. 60% of adults over 26 are married offstage and don't date. Result: +372 / −220 friend edges per month. |
| **Fights** | The same two maintenance workers fought four times in five days, at work, and got banned from the mall they work in. | Fights only happen in public, never mid-shift, with a 14-day cooldown per person. Staff get written up instead of banned. |
| **Rumors** | Rumor heat grew without limit (heat 55). One rumor could spawn several near-identical exaggerations. | Heat is capped at 10. Each rumor mutates at most once, into a single exaggerated variant ("caught stealing" becomes "arrested for stealing"). |
| **Arcade** | 19–23 "new record" events a month, because the seeded high-score boards were weak. Machines broke about every other day. | Boards are seeded from 60 skilled attempts, and machine wear tolerance is higher. Records now fall about 3 times a month and mean something. |
| **Player jobs** | Shifts paid for 1 hour regardless of length, because pay was computed after the time skip. | Clock-in time is recorded, and pay covers clock-in to end of shift. |
| **Determinism** | Two runs with the same seed diverged after about a week. | Lua 5.4 randomizes string-key hash order per state, and `Social.update` walked `pairs(areas)` while drawing from a shared RNG. Areas are now visited in sorted order. Same seed plus same inputs now gives an identical timeline (checked by hashing three runs). |
| **Save size** | 966 KB JSON. | NPC plans and in-flight routes are rebuilt on load and no longer saved. Floats are rounded. Integer sets are stored as id lists. Now about 790 KB. |

## The three weakest systems, and how I deepened them

The runs after these fixes still flagged three systems that barely moved:
**store-to-store relations** (0 feuds in 30 days), **romance** (3 couples, 3
breakups, no dates), and **arcade competition** (a monthly tournament was
announced in the timeline but did nothing).

### 1. Store politics and mall management (`sim/management.lua`)
- **Neighbours affect trade.** An arcade next door hurts a bookstore and helps
  a game store. A department store feeds the shoe and clothing stores next to
  it. A busy neighbour sends shoppers past your window.
- **Relations drift** with friction and synergy by store type (noise, smells,
  direct competition). Neighbours start with some history.
- **Feuds produce incidents**: trash carts parked in front of windows,
  competing sales, notes that end with "regards". The feuding stores lose
  popularity and their staff come to dislike each other.
- **Management mediates** long feuds and fines one side.
- **The general manager reviews the mall every week and sets policy**, and the
  policies change NPC behaviour:
  - a Parental Escort Policy sends under-16s home at 6 PM on weekends;
  - No Loitering pushes teens from the fountain to the food court;
  - No Wheels means fewer skaters come;
  - an Extra Security policy hires a new guard NPC;
  - Teen Night gets suspended and later reinstated by petition;
  - falling traffic triggers promotions.

### 2. Romance (`sim/romance.lua`)
- **Crushes engineer coincidences.** After plans are made, people with crushes
  change theirs to be where their crush will be. That extra co-location is
  what lets relationships develop.
- **Couples go on dates**: movies (both actually watch the same showing),
  dinners, the food court, the arcade. Dates are more likely on weekends and
  near-certain on Valentine's Day.
- **Anniversaries** at 1, 3 and 6 months and every year go into the timeline.
- **Cheating leaks through the rumor mill.** A partner's friend sees the
  hand-holding, the rumor spreads, and when it reaches the partner they break
  up. Sometimes the cheater ends up with the other person.
- **Dating the player comes with expectations.** Your partner pages you, gets
  hurt if you disappear for a week, and remembers if you forget Valentine's
  Day. If attraction drops too low, they break up with you.

### 3. Arcade competition (`sim/arcade.lua`, `scenes/play.lua`)
- **Monthly tournaments.** Skilled and eager NPCs change their Saturday plans
  to enter (36–41 entrants in test runs). Everyone's best run counts. The
  winner is settled at 5 PM and gets 500 tokens, a timeline entry and a rumor.
  You can enter by playing the tournament cabinet during the window.
- **Rivalries.** An NPC who takes your record becomes your rival: they page
  you, taunt you in the concourse, and can be challenged head-to-head for 10
  tokens. They play first and you have to beat their score.
- **Cabinet rotation.** Each month the arcade replaces its least-played novelty
  machine.

## Current numbers

### 30 days (seed 1997, with the autopilot player)

These numbers are from after the fix for Playdate's 32-bit integers, which
changed the RNG's output, so seed 1997 now generates a different mall than
the one in earlier drafts of this document.

- **Mall:** 135 stores (3 department stores, 11 food stalls, cinema, arcade),
  499 NPCs, and 97–185 named people physically in the mall at noon or 7 PM.
  On top of those, the concourses and food court show an anonymous crowd
  sized from the day's footfall (see below).
- **Stores:**
  - 19 stores' popularity moved by 8 or more points;
  - 62 of 138 stores were profitable in the last week, 26 are in trouble
    and 17 are running sales. (Cash now falls at most stores over a month,
    because owners take profits out; see "Year two" below.)
  - six closings were announced, with liquidation sales;
  - four managers were fired and replaced, and six more were brought in
    from out of town;
  - four new tenants opened, shaped by current trends.
- **People:**
  - 20 hires, 7 quits and 12 manager changes;
  - 7 new couples and 21 partner changes, plus dates and anniversaries;
  - 512 of 517 NPCs visited the mall, averaging 8.8 distinct areas each.
- **Rumors:** 56 live rumors. Mall myths reach up to about 215 people. The
  player bot's new job was heard about by 208 NPCs.
- **Crime:** 49 NPC thefts, 17 caught.
- **Arcade:** a tournament with 43 entrants and 7 new records.
- **Save:** about 714 KB.

Across seeds 7, 42 and 1234, the same 30 days produce:

| | Feuds | Closures | Couples | Manager changes | Openings |
|---|---|---|---|---|---|
| Range | 0–1 | 0 | 6–10 | 9–10 | 4 |

No store finishes closing in the first month: stores that announce
closing still have a liquidation sale running when day 30 ends.

### 150 days (seed 1997, to late January 1998)

- **Stores:** 34 closures, 27 openings, 18 feuds and 43 manager changes.
- **People:** 32 couples and 25 breakups.
- **Crime:** 134 thefts (63 caught) and 8 store security upgrades.
- **Calendar and management events:** a No Wheels policy, Black Friday, the
  mall Santa, *The Unsinkable* opening on Dec 19 (which started a trend),
  New Year 1998, and the fountain renovation.
- **January slump:** 20 of 128 stores were profitable in the last week.

## After the first Simulator runs

Running the game in the real Simulator, rather than my headless mock, turned
up two problems that the tests could not see:

- **Walkers hopped.** The world ticks once per game minute (every 30 frames),
  and NPC positions were only computed at those ticks. Anyone walking jumped
  about 90 pixels once a second. The display now interpolates within the
  minute. Route times are also kept relative to the minute each walk started,
  so they stay precise in Playdate's single-precision floats however late
  in the game it is.
- **The mall looked empty.** At 3:25 PM on a Friday about 200 named NPCs were
  in the mall, but most of them were staff inside stores. Only about 10 were
  out in two long concourses, so the player usually saw nobody.
  - Named shoppers now window-shop on their way to stores, standing at the
    glass facing in.
  - The rest of the day's footfall (the 3,000–8,000 visitors a day the store
    economics already count) now appears as an ambient crowd
    (`ui/crowd.lua`). The crowd is derived and never saved: each extra is a
    function of the seed, area, index and time. Extras stroll a stretch of
    open floor and stop at shop windows. Their number follows the day's
    footfall and the hour, so a Saturday afternoon or Black Friday is
    packed, and a January weekday morning is nearly empty.

## Year two

A 400-day run (`lua5.4 tools/sim30.lua 1997 400 --bot`) showed the store
economy going flat in the second year:

- By September 1998, 94 of 127 stores were profitable.
- Only 2 were in trouble.
- Even the bottom tenth of stores held $6,400 in cash.

Three things caused this:

1. **Survivorship.** Weak stores closed and were replaced by better ones.
   Average store quality climbed from 0.47 to 0.68 over the year.
2. **Rents never moved.** Each store's rent was set on opening day, so a
   store that did well paid a smaller and smaller share of its sales.
3. **Cash only piled up.** A store with a $25,000 cushion could not get into
   trouble however bad a season was.

What changed:

- **Annual lease renewals** (`Stores.leaseCheck`). Each lease is re-priced
  against the store's last eight weeks of sales. The rent goes up at least
  3% and at most 35%. A store that is in trouble and in debt gets rent
  relief instead. Big increases and rent cuts go into the timeline.
- **Owners take profits out.** Each week, half of any cash above four weeks
  of operating costs leaves the store.
- **Stores go stale.** Without a trend behind it, a store slowly loses
  quality. A store with money can **remodel** to win it back ("closed for a
  weekend and reopened with a new look").
- **The outlet mall competes.** From April 1998, clothing, shoe, sporting
  goods and department stores lose some of their share of shoppers.
- **Departed NPCs are compacted.** A month after someone moves away, they
  keep their name, look and relationship with the player. Their
  possessions, wants, secrets and ties to everyone else are dropped. The
  save at day 400 went from 1.5 MB to 1.3 MB.

After the changes, the same 400 days show:

- Store closings every month of 1998: a wave of 7–8 a month through the
  spring, after the January slump and the outlet mall opening, then 1–3 a
  month.
- 4–8 openings a month.
- Lease renewals throughout the year and manager changes every month.
- 86 closures and 76 openings in total.

Summer is still easy on stores. 1998 summer footfall is about 30% above the
spring, and by late September 1998 only 4 stores are in trouble, against 23
in January.

