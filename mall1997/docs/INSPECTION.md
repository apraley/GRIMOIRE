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

## Current 30-day numbers (seed 1997, with the autopilot player)

- **Mall:** 136 stores (5 department stores, 11 food stalls, cinema, arcade),
  508 NPCs, and 110–185 people physically in the mall at noon or 7 PM.
- **Stores:**
  - 19 stores' popularity moved by 8 or more points;
  - cash went down at 72 stores and up at 64;
  - 22 stores are in trouble and 13 are running sales;
  - 2 closed and 3 new tenants opened, shaped by current trends ("Zoot &
    Suit" during the swing revival);
  - 2 feuds, with incidents and mediation.
- **People:**
  - 29 hires, 7 quits and 3 manager changes;
  - 6 new couples, 7 breakups and 27 partner changes;
  - 519 of 523 NPCs visited the mall, averaging 8.8 distinct areas each.
- **Rumors:** 53 live rumors. The most widespread are mall myths that 100–290
  people have heard. Exaggerated variants appear ("Nadine is secretly engaged
  to...").
- **Crime:** 43 NPC thefts, 17 caught, and one store upgraded its security
  after a wave of thefts.
- **Arcade:** a tournament with 30+ entrants and 3 new records.
- **Player bot:** hired as a restaurant clerk and promoted to shift lead. It
  was caught once and got away with one theft, saw several movies, and 46 NPCs
  heard rumors about it.
