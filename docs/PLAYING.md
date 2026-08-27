# Playing GRIMOIRE

A strategy guide: what each background is actually good at, how to spend
action points, how heat and pursuit work and how to manage them, how to turn
a surveillance report into a compliant cabinet minister, how the seven
victory paths differ in what they actually demand of you, how to make money
at scale, and the ordinary ways games end early.

For what the underlying simulation is doing while you play, see
[`SYSTEMS.md`](SYSTEMS.md). For the exact numbers behind everything named
here, see [`CONTENT.md`](CONTENT.md).

## Contents

- [Backgrounds](#backgrounds)
- [Action points: the daily economy of time](#action-points-the-daily-economy-of-time)
- [Heat, exposure and pursuit](#heat-exposure-and-pursuit)
- [Building leverage on people](#building-leverage-on-people)
- [The seven paths, and what opening suits each](#the-seven-paths-and-what-opening-suits-each)
- [Money](#money)
- [How games actually end](#how-games-actually-end)

## Backgrounds

Every background sets starting wealth, a handful of pre-trained skills,
attribute bonuses, and one or two permanent perks (`grimoire/player.py`
applies them at character creation; the full numbers are in
[`CONTENT.md`](CONTENT.md#character-backgrounds)). What matters in play is
less the starting cash than the perks — they're permanent and shape which
victory paths are cheap for you versus expensive.

- **Dynastic Heir** — old money (compounds at +3%/yr) and a hereditary
  legislative seat from day one (`family_seat`), plus finance/etiquette/
  networking. The natural opening for **capital** or **hegemony**: you start
  already inside the system other backgrounds spend their first hundred
  days trying to enter.
- **Burned Operative** — tradecraft, infiltration, surveillance, forgery,
  and three already-placed intelligence contacts (`old_network`) plus a
  spare clean identity (`ghost_identity`). Built for **deep state** and
  **covert conquest**: you can run `surveil` → `blackmail` chains from day
  one without first having to build the relationship that makes them work.
- **Tech Founder** — engineering, finance, hacking, and faster personally-led
  research (`engineer_mind`) plus investors who fund on a handshake
  (`capital_access`). The straightest line to **singularity**: you already
  have the skill mix `study` and `project` actually reward.
- **Sidelined General** — command, strategy, combat, and a standing head
  start of trust and respect with every serving general, admiral and air
  marshal in your home nation (`officer_corps`), which makes `persuade` and
  `recruit` against any of them measurably easier from turn one (both
  actions weigh directly on the target's disposition toward you).
  `war_college` is flavour text with no separate code effect. Built for
  **conquest**, and a strong `coup`/`coup_prep` opening once you've
  `travel`led somewhere with weak army loyalty.
- **Movement Demagogue** — oratory, propaganda, politics, and a standing
  base of supporters that grows with fame (`mass_following`), plus guaranteed
  media coverage (`media_gravity`, which cuts both ways). The natural
  **creed** opening: `speech` and `preach` compound fast when you start with
  followers already.
- **Shadow Banker** — the best finance/accounting stats in the game, plus a
  flat 35% discount on all heat gained from anything you do
  (`regulator_friends`, mechanically a general heat resistance rather than
  something specific to financial scrutiny). `dark_pools` is flavour text
  with no separate code effect. Built for **capital**, and for laundering
  everyone else's dirty money too if you want an ongoing income stream that
  isn't public equity.
- **Syndicate Underboss** — smuggling, intimidation, networking, combat,
  and a syndicate you already control outright (`underworld_ties`) plus
  standing enforcers (`muscle`, which reduces the effective difficulty of
  `threaten`). A fast, dirty opening toward **deep state** through fear and
  debt leverage rather than blackmail, or toward **capital** through racket
  income laundered at scale.
- **Heretic Scientist** — the highest starting `science` in the game, plus
  a laboratory nobody audits (`lab_access`, which speeds `study`) and
  scientists who share unpublished work (`peer_respect`). A second, slower
  **singularity** opening: less starting cash than the Founder, more raw
  research throughput.
- **Schismatic Cleric** — theology, oratory, and a tithing congregation
  (`flock`). The other **creed** opening — `found faith` instead of
  `found movement`, and adherents count toward creed victory the same way
  followers do.
- **Investigative Journalist** — surveillance, networking, propaganda, and
  secrets that surface to you unprompted (`sources`, which seeds several
  secrets on random people at character creation). Underrated for
  **deep state**: you start already most of the way through the surveil
  step of the leverage pipeline below.
- **Career Diplomat** — diplomacy, languages, etiquette, negotiation, plus
  the highest starting spread of relationship-building skills in the game.
  The natural **hegemony** opening: `treaty` and cross-nation relationship
  work are your starting strengths.
- **Nobody At All** — nine thousand dollars and almost no skills, but the
  `clean_slate` and `underestimated` perks are pure flavour (there is no
  code path that reads them; every background actually starts at zero heat
  and zero exposure regardless — see [`SYSTEMS.md`](SYSTEMS.md#the-player)).
  What you actually get is the lowest floor in the game and nothing to fall
  back on: the hardest opening, and, by design, the one where every later
  achievement is entirely self-made.

## Action points: the daily economy of time

Everything you do costs action points out of a daily budget. The formula
(`player.py:tick_player`) is:

```
ap_max = round(3 * (1 + trait_ap) * (0.55 + 0.45*health) * (1.15 - 0.35*stress))
```

`trait_ap` sums modifiers from your traits (`workaholic` and `ambitious` both
add to it). At full health and low stress that's close to 4 AP some days; at
half health and high stress it can fall to 1. AP resets to `ap_max` every
morning — unspent AP does not carry over, so ending a day with points on the
table is a pure loss. Most single actions cost 1 AP; recruiting, acquiring
an organisation, and several 2-AP covert operations cost more; `coup`,
`false_flag` and `declare_war` cost 3 — effectively your entire day.

Two things eat AP budget without producing anything on their own: health and
stress. `rest` costs 1 AP but returns a large chunk of both, and is very
often the correct move before a day you intend to spend on something
expensive — an extra point of AP from better health pays for itself inside
a week. `indulge` is a faster stress reliever but risks addiction and (at
higher notoriety) a `ridicule` narrative about you; it's a short-term tool,
not a routine.

Money and AP are usually not the same bottleneck at the same time: early
game, money is scarcer than AP (most useful actions cost more cash than a
new character has); mid-to-late game, once income streams exist, AP becomes
the binding constraint and the question shifts from "can I afford this" to
"is this the best use of today."

## Heat, exposure and pursuit

Heat (0-1) is how much attention you've drawn; exposure (0-1) tracks how
close that attention is to being *attributed* to you specifically. Both
decay passively (~0.12%/day, faster in hiding), so heat is a resource you
spend down over time as much as one you build up. `HEAT_STAGES` names seven
bands from *unknown* (no file exists) through *noted*, *watched*,
*investigated*, *wanted* (warrants exist, travel becomes a calculation),
*hunted* (task forces actively looking), to *priority_target*. Check your
current stage any time with `status` or `intel`.

Every covert operation carries a base exposure risk from its `risk` figure
(see [`CONTENT.md`](CONTENT.md#intelligence-operations)); a **failed**
operation is roughly 1.8x more likely to be exposed than a successful one,
so a rushed, underfunded operation against a hard target is the worst
possible trade — you pay the AP and money either way, and failure raises
your odds of being caught doing it. If an operation is exposed, a separate
roll decides whether it's *attributed* to you specifically, weighted by the
victim nation's intelligence capacity; an attributed exposure adds that
nation to your `wanted_by` set and starts a live pursuit risk against you
whenever you're inside reach of their intelligence and state capacity.

Practical heat management:

- **`hide`** doubles your passive heat decay rate and stops most forms of
  new exposure, at the cost of the AP you'd otherwise spend advancing
  anything. Use it as a deliberate cooldown after a bad exposure, not as a
  permanent state — you cannot run an empire from a basement.
- **`identity`** (money, 1 AP) builds a second clean legend; `identity
  switch <n>` moves your *current* heat onto the old identity's ledger and
  resumes at whatever heat the new one is carrying (zero, for a fresh one).
  This is the single best tool for resetting to `unknown` without actually
  stopping.
- **`counterintel`** (against a nation) sweeps your own organisation for
  moles and directly reduces your heat and exposure on success — worth
  running proactively once you're operating inside a hostile nation's
  borders, not just after you suspect a leak.
- Fund operations properly. `_launch` lets you overspend the reference
  `cost` for a faster ETA and effectively higher funded skill; underfunding
  to save money is usually a false economy once you account for the
  elevated exposure risk of the resulting lower success chance.
- If you *are* on a nation's wanted list, staying out of their borders (and
  the borders of nations that share an extradition treaty with them) is the
  cheapest form of safety there is — `_pursuit` reach is discounted sharply
  outside the hunting nation's own territory, more so if your host nation
  actively dislikes them.

Getting caught is not automatically fatal, but it is expensive: an arrest
holds you for `360 * (1 + heat*6)` days — a year at minimum, several years
at high heat — with your options reduced to waiting and thinking. That's
real, permanent progress lost on every other clock in the game (rivals keep
climbing, elections keep happening, wars keep being fought) while you sit.

## Building leverage on people

The core social-engineering loop, and the fastest route into a cabinet,
boardroom or party leadership you didn't have to win honestly:

1. **`surveil <person>`** — establishes a pattern of life and, on success,
   has a chance to surface each of that person's hidden secrets (severity-
   weighted; a `murder` secret at 0.95 severity is a near-certain career-
   ender if surfaced, an `illness` at 0.35 is a much weaker lever). It also
   reports their role, influence, wealth, loyalty and corruptibility — the
   numbers that tell you whether blackmail, a bribe, or a straight `recruit`
   pitch is the efficient move against this particular target.
2. **`blackmail <person>`** — only works on a secret you actually
   `known_by` hold; it converts that secret into obedience (the target's
   `blackmailed_by` flag, plus a large `fear` bump and a `trust` cut in your
   relationship with them) at a success chance driven by the secret's
   severity. A refused blackmail attempt is expensive: the target's
   suspicion rises sharply and they become an active enemy, so only pull
   this trigger on a secret severe enough to make refusal implausible.
3. Alternatively, **`bribe <person> | <amount>`** works without needing a
   secret at all, priced off their influence and discounted by their
   corruptibility — cheaper against a corruptible target, and an offer that
   comes in under roughly half the estimated price is likely to be refused
   *and remembered*. **`threaten`** achieves a similar fear-based lever
   through intimidation instead of information, at the cost of trust and
   affection and a small permanent heat increase even on success.
4. Once you hold real leverage (debt, fear, or an outright blackmail flag),
   **`favour <person> | <ask>`** spends it for a concrete, role-appropriate
   payoff — a finance minister redirects a state contract to you, a general
   quietly loosens army loyalty to the government, a media baron's outlet
   starts running your line, a judge misplaces a file with your name on it.
5. For someone you want *permanently* rather than transactionally,
   **`recruit <person>`** (2 AP) turns them into an asset in your service
   outright — success chance is driven by their existing loyalty and
   disposition toward you (which `meet`, `cultivate` and prior favours all
   move), discounted by whatever leverage they already hold over the
   relationship in the other direction.

`meet` and `cultivate` are the low-cost, low-risk versions of the same
relationship-building loop, worth running on anyone whose role you expect to
matter before you need anything from them specifically — trust and
affection built early make every later ask cheaper.

## The seven paths, and what opening suits each

Run `goals` at any time for live scores; the underlying thresholds
(`victory.py:evaluate`) are worth knowing so you can tell whether a given
day's work actually moved the number that matters:

- **Conquest** needs effective control (`>0.55` counted) of nations whose
  combined population is 60% of the world's. Direct rule, puppet states, and
  owned heads of state/cabinet all count toward "control." Best suited to
  the **General** (`coup`/`declare_war` from day one) or a long, patient
  **deep state** run that converts into conquest once enough governments
  are already yours in substance.
- **Hegemony** needs 55%-of-GDP-weighted alignment among the great powers
  specifically — you don't need to touch a small state at all if you own
  enough of the nations that actually move the world. The **Diplomat**'s
  `treaty` skill and the **Heir**'s existing seat both shortcut the initial
  access this path is otherwise slow to build.
- **Capital** needs owned corporate revenue equal to roughly 35% of world
  GDP — reachable through `invest`/`acquire` on existing firms as much as
  `found`ing your own; the **Banker** and **Heir** start closest, but this
  is the path most background-agnostic once income compounds, because money
  makes money regardless of which skills produced the first dollar.
- **Creed** needs a faith or movement's adherents/followers to reach 50% of
  world population — the slowest-compounding early, fastest-compounding late
  path, because `speech`, `preach` and narrative spread all scale with
  existing reach. The **Demagogue** and **Cleric** both start with a
  standing base that makes the early, slow part of this curve much shorter.
- **Deep State** needs 65%-of-power-weighted control of world leadership —
  heads of state, heads of government, and cabinets — held through
  ownership, blackmail, debt or fear rather than office. The **Operative**,
  **Journalist**, and **Underboss** all start with either the surveillance
  skill or the pre-existing leverage this path is built from.
- **Singularity** needs the Singularity Engine megaproject complete
  (`recursive_design` + `fusion_ignition` prerequisites, both deep in the AI
  and energy trees) plus a commanding lead in privately-known technology.
  This is a long `study`/`project`/`invest_project` grind regardless of
  background, but the **Founder** and **Scientist** start with the research
  throughput and money, respectively, that make the grind shortest.
- **Apotheosis** needs the mean of your three best other scores to clear
  72% — not a separate strategy so much as the natural end-state of playing
  two or three of the other paths seriously at once rather than committing
  to a single one early. It rewards generalist late-game play more than any
  specific opening.

## Money

Starting wealth only lasts as long as it takes to found your first serious
income stream. The main levers:

- **`found <kind> | <name>`** charters a corporation, bank, party, faith,
  syndicate, media outlet, movement, private intelligence agency, or NGO for
  a kind-specific seed cost (a corp is comparatively cheap at $2.5M; a bank
  is $40M). A founded corp starts with no industry assigned — follow with
  **`expand <org> | <industry> | <amount>`** to put capital to work; the
  region it lands in is chosen automatically for best fit.
- **`invest <org> | <amount>`** buys equity in any *public* company at its
  current valuation (a single purchase is capped at 35% to keep one player
  from instantly cornering a firm's price); cross 50% ownership and you gain
  outright control of the board. **`acquire <org>`** (2 AP) buys a firm
  outright, public or not, at a premium over its valuation, and can simply
  fail if the target's leadership resists — dependent on your `finance`
  skill against their loyalty and disposition toward you.
- **`launder [amount]`** converts `dirty_money` (from robbery, extortion,
  bribery, racket income, and similar) into clean money for a fee that falls
  with your `accounting` skill, having a controlled bank on hand, and
  certain perks/technologies; running dirty balances unlaundered for long
  raises heat passively.
- **`corner <good> | <amount>`** buys enough of a single commodity to move
  its world price directly, sized against a month of world demand for that
  good; **`unwind <good>`** liquidates the position later for a cut. This
  is a genuine commodities play against the same world market nations trade
  into — a large enough position visibly moves the price other actors pay,
  which is also what makes it visible.
- **`racket <syndicate> | <kind>`** opens a criminal line of business inside
  a syndicate you control (ten kinds, from smuggling and protection to
  cybercrime and bribery networks); it's reliable income at the cost of
  accruing racket heat that eventually invites a police crackdown if left
  unmanaged.

## How games actually end

The obvious loss is **death** — from a wound left untreated, from health
that drops to zero under sustained wounds/addiction/age, from an
age-and-health-scaled random illness roll every month once you're past
sixty, or from a successful assassination attempt by someone who hates you
enough (`player_rel.trust < -0.6`) and is powerful enough to try. `treat`
and keeping your wound count down are not optional late-game maintenance —
they are the difference between finishing a run and not.

**Extinction** ends every run simultaneously: the global doomsday counter
(nuclear war, runaway climate change, engineered pandemics all push it) hits
its ceiling and there is no longer a world left to take over. This is a slow
background risk you can accelerate by recklessly funding wars and false
flags between great powers, or by simply doing nothing while the world's own
tensions run long enough on their own.

Short of an outright ending, the most common way a promising run stalls out
is **arrest** — heat mismanaged into a `wanted`/`hunted` status, followed by
a failed evasion roll, followed by a year-plus in custody with every other
clock in the world still running. It rarely ends the game by itself, but it
is frequently what turns a leading run into a losing one: rivals you were
ahead of keep climbing, elections you needed to win happen without you, and
whatever operation was mid-flight resolves without your further input.

Finally, plenty of runs simply **stall** — heat managed too conservatively
(hiding constantly, never taking the risk that actually moves a victory
score), or income never scaled past covering upkeep, or AP spent on
low-leverage actions (repeated `network` calls long after the easy contacts
are exhausted) instead of the specific chain of actions a chosen path
actually requires. `goals` is the honest check against this: if the numbers
haven't moved in a while, the day's actions weren't aimed at anything that
counts.
