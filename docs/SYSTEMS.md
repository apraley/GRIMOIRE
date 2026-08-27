# Systems

A technical tour of GRIMOIRE's simulation, subsystem by subsystem: what state
each one holds, what its daily tick actually computes, and — critically —
what feeds into what across subsystem boundaries. This is the document to
read to understand *why* the world behaves the way it does, or to safely
modify it.

For the static data tables these systems consume (goods, industries, techs,
units, ideologies, and so on), see [`CONTENT.md`](CONTENT.md). For how a
player actually uses these systems to win, see [`PLAYING.md`](PLAYING.md).

## Contents

- [The tick loop](#the-tick-loop)
- [World generation (one-time)](#world-generation-one-time)
- [Economy](#economy)
- [Society](#society)
- [Power](#power)
- [World (research, environment, individual agency)](#world-research-environment-individual-agency)
- [Covert](#covert)
- [The player](#the-player)
- [Cross-system feedback loops](#cross-system-feedback-loops)

## The tick loop

`grimoire/engine.py:tick()` is the entire daily update, called once per
in-game day from the shell's `wait` command. The order is fixed and matters —
every later stage in the list can read state a stage above it wrote this same
day:

1. **Scheduled callbacks** (`w.due()`) — deferred effects like nuclear
   retaliation, queued from `w.schedule(days, kind, payload)`.
2. **Economy** — `tick_economy`, `tick_firms`, `tick_markets_sentiment`,
   `tick_labour`, and (every 10 / 5 days respectively) `tick_reallocation`,
   `tick_inequality`.
3. **Society** — `tick_population`, `tick_migration` (weekly),
   `tick_health`, `spread_epidemics` (every 2 days), `maybe_outbreak`,
   `tick_information`, `tick_media`, `tick_faith`, `tick_culture`.
4. **Power** — `tick_politics`, `tick_unrest`, `tick_elections`,
   `tick_diplomacy`, `maybe_declare_war`, `tick_wars`, `tick_insurgency`,
   `tick_military`.
5. **World** — `tick_research`, `tick_environment`, `maybe_disaster`,
   `tick_people`, `tick_crises`.
6. **Covert** — `tick_agency_ops` (national intelligence services acting on
   their own initiative), `tick_crime`, `tick_operations` (resolving
   anything, player or NPC, whose ETA has arrived).
7. Every 3 days, `w.recompute_globals()` — global population, GDP, the
   great-power list, world tech level.
8. If a player exists: `tick_player` (daily upkeep) and player megaproject
   progress.
9. `w.clock.advance()`.

Only operation results belonging to the player (`actor == "PLAYER"`) are
returned up to the shell for display; everything else in the tick still runs,
it's just not narrated unless it produces a `w.report(...)` news item.

## World generation (one-time)

World generation (`grimoire/worldgen.py`, `worldgen_social.py`,
`worldmap.py`) runs once, at `generate_world(seed)`, and produces the entire
starting state the daily tick then evolves. It is fully deterministic in a
given seed via the stream-separated RNG (`grimoire/rng.py`): every subsystem
draws from its own named sub-stream (`rng.sub("planet")`,
`rng.sub("regions")`, …), so adding a die roll to one generator doesn't
reshuffle the history of any other.

**Planet** (`worldmap.py:generate`). A 160×76 tile grid, wrapping
east-west. Continental blobs plus island scatter, warped by fractal value
noise; 9-14 tectonic plates assigned by discretised Voronoi with drift
vectors; convergent boundaries raise elevation, divergent lower it; a
smoothing pass; sea level calibrated to hit a target land fraction
(25.5%-32.5%) by picking the elevation percentile that matches. Temperature
follows a latitude quadratic and an altitude lapse rate. Moisture
(`_moisture`) is the most elaborate piece: a genuine wind-and-orography
model — prevailing wind direction flips by latitude band, a "carry" value is
depleted by orographic rainfall (`rise = max(0, elev - prev) * 11.0`,
deposited as `carry * (0.05 + rise)`) as it crosses each row, and a
Hadley/Ferrel latitude-band function scales the baseline. Biomes are a
lookup on temperature/moisture/elevation; rivers trace downhill from wet
highland sources; resources cluster in geological blobs (weighted by biome
mining bonus for hard-rock/ore kinds); continents are flood-filled and named.

**Regions and nations** (`worldgen.py:carve_regions`, `form_nations`).
Regions are grown from habitability-weighted seeds by randomised BFS (organic
shapes, not administrative squares). Nations are grown the same way from
region seeds sized by a Pareto draw (`rng.pareto(1.25, 2.2)`) — a
power-law of national sizes. Each nation draws a development archetype
(advanced/industrial/emerging/frontier/extractive) that seeds its
GDP-per-capita band, tech level, education, infrastructure, urbanisation and
life expectancy range; population is distributed across regions by a
habitability/arable/fishery/coastal score, then split by age band via a
demographic-transition formula (`young = 0.42 - 0.30*dev`, `old = 0.05 +
0.26*dev`) and by wealth band via national Gini.

**Technology, economy, institutions.** Nations get technologies whose
research-point cost fits inside a development-scaled budget, gated by
prerequisites, with weapons-of-mass-destruction techs deliberately *not* a
pure function of wealth (`rng.chance(0.16)` regardless of budget fit).
`io_balance.allocate` is run once per nation to size its starting industry
mix from scratch — see [Economy](#economy) below for what that function does
on every subsequent day too. Stockpiles are seeded to roughly 12-40 days of
cover (more for perishables' shorter cover, more for strategic goods) so the
game doesn't open mid-shortage. Governments, ideology vectors, parties,
faiths, the full named population of heads of state/cabinets/generals/
CEOs/clerics/spies/etc. (`populate_people`), corporations/banks/media/
syndicates/universities (`make_orgs`), militaries sized against budget and
domain, and pairwise relations/treaties/claims are all generated from these
seeded fundamentals in that order, each layer consuming the layers below it.

## Economy

**State.** Per-nation: `stockpile` (a `Counter` over every good), `prices`,
`policy` (25 sliders), `treasury`/`debt`/`fx_reserves`/`credit_rating`,
`gdp`/`growth`/`inflation`/`unemployment`. Per-region: `capacity` (industry →
jobs), `output` (good → units/day), `employment`, `wage`, `capital_stock`.
Global: `WorldMarket` — a single `price`/`stock`/`supply`/`demand` per good,
acting as the buffer every nation trades into.

**The Leontief solve** (`io_balance.py`). `final_demand(w, nat)` computes
units-per-day demanded by households (the `BASKET` table, split poor/middle/
rich by wealth share — this is the anchor of the whole system), then sizes
investment, government, military and research demand as *value shares* of
that household total (so the composition of GDP stays realistic without a
GDP-level feedback loop). `expand(w, nat, final)` is the actual Leontief
step: it repeatedly walks each unit of demand for a good back through the
industries that produce it and adds the *inputs* those industries need,
round after round (capped at 14, and cut off once the residual demand wave
falls below 0.01% of the original), so that final demand for foodstuffs
correctly implies derived demand for fertilizer, which implies gas and
chemicals, and so on down the tree. `required_jobs` and `allocate` turn that
physical-output vector into a jobs-per-region allocation: `allocate` computes
jobs from *actual* regional productivity (not a flat national average, or
allocation and realised output permanently disagree), rescales globally to
fit the actual workforce, and blends toward the new allocation slowly
(`tick_reallocation` calls it with `blend=0.04` every 10 days) rather than
snapping — industries don't re-site overnight.

**Daily production** (`economy.py:produce_nation`, called from
`sim_economy.tick_economy`). Every region's unconstrained plan
(`plan_region`, cached until capacity changes or 10 days pass) is summed
into national input requirements. Inputs are rationed **nationally** first —
a shortage is shared proportionally across every plant that needs the good,
rather than whichever region's loop runs first draining the tank. Before
rationing, a spot-buy pass (`_spot_buy`) tries to cover part of the gap from
the world market, spending FX reserves and treasury, which is what keeps a
single missing input from cascading into a nationwide production collapse.
Output is *also* capped by warehouse room: a target stock cover
(`cover_target` — 12 days for perishables, 40 for durables, scaled up for
strategic goods and wartime mobilisation) plus a 40% margin, checked against
the stock level *before* this tick's imports (using post-import stock here
was an earlier bug that made every import look like a domestic glut and
choked off production nationwide — the code comments call this out
explicitly). Idle jobs (capacity minus jobs actually used) don't disappear:
a subsistence-farming floor lets them feed people directly, which is what
keeps a small, import-starved economy from spiralling to literal zero output.

Total factor productivity (`tfp()`) is the single place technology,
infrastructure, education, war devastation and control all multiply
together: technology enters **convexly** (`t = BASE_TFP + 2.0 * tech **
(1.6 + 1.6*skill)`), and more convexly the more skill-intensive the process —
a poor country can still farm at reasonable efficiency, but cannot run a fab.
This convexity is explicitly what produces the ~40x rich/poor productivity
spread the game exhibits. Devastation (`1 - 0.55*devastation`) and lost
government control (`0.55 + 0.55*control`) both multiply straight into this
same term, which is the mechanical heart of the war→economy feedback loop
described below.

**Prices, trade, accounts.** `clear_prices` moves each national price toward
the level implied by the local supply/demand gap (elasticity-scaled),
arbitraged toward the world price by an openness term (tariffs and capital
controls widen the gap that's allowed to persist). `clear_world_market`
prices the *global* buffer off **days of cover**, not instantaneous flow —
pricing off a slow-moving inventory signal instead of daily noise is what
keeps world prices from becoming a high-frequency oscillator while still
reacting hard to a genuine multi-week shortage. `tick_trade` is a shared
warehouse model: nations deposit surplus above their cover target and draw
down deficits below it, subject to an openness multiplier built from
tariffs, capital controls, blockade status, war, sanctions count, and the
global `trade_openness` figure (itself driven by great-power tension).
`national_accounts` rolls value added into GDP (a 90/10 exponential smooth,
not the raw daily figure — noise doesn't leak into headline growth), taxes
revenue by a compliance-adjusted rate against the 25-lever policy vector,
computes the budget balance, and sets the inflation target as a function of
money growth, imported price pressure, debt-to-GDP above a 1.6 threshold,
unrest, and physical scarcity — not just an exogenous random walk.

**Firms and labour.** `tick_firms` grows corporate revenue with national
growth, sector pricing, unrest and war drag; bank profit tracks the
policy-rate/credit-spread margin against loan book size; syndicate ("crime")
org income comes straight from the racket table net of policing pressure.
Public companies' share price chases a fair-value estimate off trailing
earnings and a sentiment-adjusted multiple. `tick_labour` sets a target
employment rate from capacity utilisation, unrest, inflation above 8%, and
war devastation, and lets wages drift with inflation and labour-market
tightness.

## Society

**Population** (`tick_population`). Fertility falls with development,
education, urbanisation and health (`tfr = 6.4 - 3.4*dev - 1.9*education -
1.1*urban + ...`), further suppressed by devastation and insurgency. Deaths
use an **age-structured hazard**, not a flat crude rate: `age_factor = 0.42 +
2.0 * (65+ population share)`, so a young pyramid at a given life expectancy
dies substantially slower than an old one — this matters because it's what
lets a poor, young, war-torn nation keep a growing population even while its
life expectancy is falling. Age-band mass flows between the five bands each
tick at fixed transition rates; ageing, urbanisation and education all creep
toward development-implied targets rather than jumping.

**Migration** (weekly). People move along region adjacency toward higher
`attract()` scores (log GDP-per-capita, low unrest/devastation/insurgency,
high employment, welfare) and away from high `push()` scores (unrest,
devastation, insurgency, unemployment); destination-nation immigration
policy scales the actual flow, and war between origin and destination nation
blocks it outright.

**Epidemics** (`tick_health`, `spread_epidemics`, `maybe_outbreak`). A
genuine **SEIR** compartmental model per region per active epidemic:
susceptible → exposed → infectious → recovered/dead, with a seasonal forcing
term (`1 + season * cos(2π * day_of_year/360 + π if southern hemisphere)`),
an urban-crowding multiplier on transmission, and a control term blending
healthcare policy, state capacity, regional health and vaccine coverage.
Case fatality rate itself responds to regional health and healthcare policy,
not just the disease's baseline. New outbreaks seed stochastically weighted
toward populous, low-tech regions; existing ones spread along region
adjacency and, scaled by national tech level, jump borders by air travel.
Vaccine development accelerates once cumulative cases pass a threshold,
faster for nations holding the `mrna_platform` technology.

**Information** (`tick_information`, `tick_media`). Narratives (scandals,
conspiracies, threats, triumphs, panics, and more — twelve kinds, each with
a virality and decay rate) grow in per-nation salience based on
connectivity (tech level), media freedom, censorship pressure, and the
story's own credibility, and jump borders stochastically once salient
enough. A live narrative measurably moves the target nation's approval,
legitimacy, unrest, opinion-by-audience, or even its ideology vector,
depending on its kind — a `threat` narrative pushes militarism and
nationalism directly; a `doctrine` narrative pulls the whole ideology vector
toward whatever position it's arguing for. Media outlets drift their bias
toward their national government under censorship pressure and otherwise
toward their audience.

**Faith and culture.** Adherence shifts each region toward secularism under
modernity (tech, education, urbanisation) and toward religion under crisis
(unrest, devastation, poor health, unemployment) — the doctrine's own
`spread` coefficient scales how contagious a given faith is. Soft power
(`tick_culture`) blends wealth, media output share, media freedom, prestige
and repression (negatively) into a slow-moving national attribute that feeds
into diplomacy and the hegemony victory condition.

## Power

**Politics** (`tick_politics`). Approval is a function of growth, inflation
above 3%, unemployment above 6%, physical shortfall, war weariness, welfare/
health/education spending net of corruption, prestige and unrest. Legitimacy
follows from the government type's baseline plus approval, minus corruption,
plus state capacity, minus unrest and war exhaustion. State capacity itself
depends on tech level, education spending, legitimacy, minus corruption,
unrest and war exhaustion — and corruption's own target depends on state
capacity and media freedom (negatively) and surveillance policy net of media
freedom (positively): several of the "how healthy is this state" numbers are
mutually reinforcing rather than independent. Policy sliders drift toward
whatever the ruling ideology vector implies (weighted by each `POLICY_IDEOLOGY`
axis-to-lever mapping), at a rate set by the government type's `speed`
constant scaled by state capacity — autocracies move policy faster than
gridlocked democracies. Wartime automatically pushes military spending up and
unrest above 25% pushes surveillance/policing/censorship up, scaled by how
little media freedom is left to lose.

**Unrest, coups, revolution** (`tick_unrest`). Per-region unrest chases a
target built from grievance (unemployment, poor health, corruption,
inflation above 5%, low legitimacy, devastation, inequality above a 40% Gini
threshold, separatism) net of relief (welfare, healthcare, growth,
legitimacy) net of control (repression × state capacity, discounted by
existing insurgency). Crucially, **repression that outstrips legitimacy
breeds insurgency**: the push term is `(unrest - 0.34) * (0.4 + 0.9*(1 -
legitimacy)) * (1 + 1.4 * clamp01(control - legitimacy))` — a region held
down by force alone, with nothing underwriting that force in the population's
eyes, radicalises faster than one held by consent. Insurgency above threshold
degrades territorial control and raises devastation; below threshold, both
heal. Coups, revolutions, protests/strikes/riots, and secession are all
stochastic draws off these same state variables (army loyalty, unrest,
legitimacy, separatism), with distinct consequences — a successful coup
installs a junta-flavoured leader and spikes repression; a successful
revolution can flip the government type entirely, toward authoritarian forms
if the departing ideology already leaned authoritarian.

**Diplomacy and war** (`tick_diplomacy`, `tick_wars`). Bilateral relations
drift toward a target built from ideological distance, shared culture,
treaty depth, neighbour friction, contested claims, active war, sanctions,
and combined soft power; great powers get an extra mutual-suspicion penalty.
Wars are declared (`maybe_declare_war`) when relations are hostile enough,
the aggressor doesn't expect to lose on paper, and an "appetite" score
(militarism, nationalism, low legitimacy, active claims) clears a
probability threshold. Battles resolve front-by-front: each side's committed
power is its `military_score()` (unit count × attack/defence factors ×
morale × readiness), multiplied by doctrine bonuses, `_supply_at()`
(a function of distance from capital, infrastructure, and logistics
stockpile — an army fighting far from home on a bad road network fights
worse), and terrain defence (mountains, wetlands, rainforest all help the
defender). Losses feed back into war weariness, war exhaustion, morale, and
regional devastation/unrest directly. A losing nuclear power's desperation
(losing warscore, war exhaustion, low legitimacy) can cross a threshold that
triggers a nuclear strike, which itself raises the global doomsday clock,
world tension, and (with high probability) a scheduled retaliatory strike.

**Insurgency and military** (`tick_insurgency`, `tick_military`). Regions
deep in insurgency can tip a nation into civil war, which itself further
erodes state capacity — a war a nation is losing to itself, not another
state. `tick_military` procures new units from whatever budget remains after
upkeep (favouring land units, and doctrine/tech-appropriate expensive units
proportionally more as tech level rises), lets forces wither if upkeep can't
be paid, and advances nuclear weapons programmes probabilistically toward a
first test.

## World (research, environment, individual agency)

**Research** (`tick_research`). Research points accumulate from budget
(research policy share of GDP), university endowment, and corporate R&D
(capped at 6% of GDP, so a country can't out-research a rival purely by
letting one firm's R&D line grow without bound), scaled by average regional
education and modified by every already-held technology's own `research`
effect. A nation picks a research focus weighted by ideology (militarist
nations favour weapons, ecological nations favour energy, authoritarian
nations favour control/surveillance techs), cost, and wartime urgency; 72% of
daily research points go to the focus and the rest spill over the next five
available technologies, so the tech frontier as a whole creeps forward even
while one thing is being rushed. Technology diffuses globally: a tech gets
*cheaper* for everyone the more nations already hold it
(`cost * clamp(1 - knowers*0.03, 0.40, 1.0)`), which is what produces
believable "arrives everywhere within a generation" technology diffusion
instead of every nation researching from a blank slate forever.

**Environment.** Daily weather is a per-region random walk that mean-reverts
toward 1.0; every 10 days, emissions accrue from GDP scaled by tech level
(net of environmental policy and clean-tech effects), CO2 accumulates net of
a 55%-efficient natural sink, radiative forcing follows the standard
logarithmic CO2 relationship, temperature anomaly chases that forcing on a
slow lag, sea level rises with temperature anomaly, and the global doomsday
counter tracks both temperature anomaly and diplomatic tension. Natural
disasters (nine kinds — earthquake, hurricane, flood, drought, wildfire,
volcano, heatwave, tsunami, blizzard) fire stochastically at a rate that
itself scales with temperature anomaly, weighted toward regions whose biome
and coastal exposure fit the disaster type, with damage discounted by tech
level, infrastructure and state capacity.

**Individual agency** (`tick_people`, monthly). Every named person ages,
faces an age- and health-dependent mortality hazard, accumulates or heals
stress and health, occasionally embezzles (probability scaled by
corruptibility × national corruption, with a media-freedom-scaled chance of
being publicly exposed), and — driven by their own `ambition` stat — can
climb a defined role ladder (legislator → governor → head of government,
spy → intelligence chief, general → defence minister, and so on), displacing
a weaker incumbent. Deaths of heads of state or cabinet ministers trigger
succession: democracies promote from elected roles, autocracies promote from
the security/administrative apparatus, and the new leader's ideology pulls
the national ideology vector sharply toward their own.

**Crises** (`tick_crises`). Ten discrete geopolitical shock types (financial
panic, energy shock, cyber blackout, market crash, currency collapse, trade
war, terror attack, refugee surge, nuclear test, border incident) fire at a
rate that scales with global tension, each with its own hand-written,
immediate mechanical consequence (a currency crisis multiplies a nation's
currency and inflation and halves its FX reserves outright, for instance)
rather than a generic "bad thing happens" roll.

## Covert

**Operations** (`sim_covert.py`). Every operation — the player's or a
national intelligence service's — goes through the same three-stage model:
`op_difficulty()` computes a target-specific difficulty from the operation's
base risk plus the target's protection/suspicion (for a person), intel
capacity and surveillance policy (for a nation), or secrecy (for an
organisation); `launch_op()` sets an ETA scaled by funding relative to the
operation's reference cost and the actor's skill; and `resolve_op()`, once
the ETA arrives, runs an opposed skill-vs-difficulty check (`rng.check`,
Gaussian-noised) for success and an independent exposure roll whose
probability scales with the operation's inherent risk, the actor's skill
(inversely), and the difficulty (a failed operation is roughly 1.8x more
likely to be exposed than a successful one). A twenty-entry handler table
(`_HANDLERS`) implements what each operation kind actually does on success —
`surveil` can surface a target's secrets, `blackmail` converts a *known*
secret into obedience with a severity-scaled success chance, `assassinate`
rolls the target's protection against survival, `coup_prep` calls straight
into the same `_coup()` function `sim_power.py` uses for spontaneous coups.
Exposure, when it happens, is independently rolled for *attribution*
(whether the victim can trace it back to the actor); an attributed exposure
against the player adds them to that nation's `wanted_by` set and starts the
pursuit clock (see [The player](#the-player)); an attributed exposure by one
nation against another directly damages the relation and nudges world
tension.

**State services** (`tick_agency_ops`). Nations run this exact same
operation pipeline against each other unprompted every day, budget and
intel-capacity permitting, biased toward rivals and escalating toward
sabotage, insurgent arming, assassination and coup prep only against
nations they already relate to at -0.5 or worse. This is why a nation's
`intel_capacity`, `stability` and `army_loyalty` visibly erode over a long
game even without the player touching them — rival services are working
them too.

**Organised crime** (`tick_crime`). Syndicate heat accrues from active
racket exposure net of policing pressure (itself discounted by corruption);
crossing a threshold triggers a police crackdown that strips a racket and
cools heat; below threshold, syndicates expand into new rackets and existing
ones compound. Bribery flows from syndicate cash into national corruption
directly. City-level crime is a slow-moving blend of local syndicate
presence, regional unrest, unemployment, and policing policy.

## The player

**State** (`grimoire/player.py`). Action points (nominally 3/day, scaled by
health, stress and traits — see [`PLAYING.md`](PLAYING.md) for the exact
formula), money (with a `dirty_money` sub-total that `launder` addresses),
heat and exposure (0-1, decaying slowly on their own and faster while
`in_hiding`), `wanted_by` (a set of nations with an attributed grievance
against you), and the ordinary human-survival stack: health, stress, sleep,
nutrition, wounds, addictions.

**Daily upkeep** (`tick_player`). Needs drift each day (stress up, sleep and
nutrition down, partly offset by money and by wound-healing skill); health
heals from sleep/nutrition/medicine skill net of accumulated wound severity
and addiction burden, and falls at 0.02% health if it ever bottoms out.
Income nets holding-based dividends against a burn rate that scales with
organisation and asset count and with notoriety — running an empire has
overhead, and a more notorious operator's overhead is higher. Heat and
exposure both cool passively every day, faster in hiding; if you're on
anyone's `wanted_by` list, a pursuit check can fire (`_pursuit`), scaled by
the hunting nation's intelligence and state capacity against your tradecraft
skill and identity status, and a failed evasion roll means arrest for a
heat-scaled prison term. A separately-rolled assassination-attempt check
fires against a sufficiently hated, sufficiently powerful enemy, independent
of the pursuit system.

## Cross-system feedback loops

These are the loops that make the simulation feel alive rather than scripted
— they are not special-cased anywhere; they emerge from the state variables
listed above being read and written by more than one subsystem.

**War → devastation → unrest → insurgency → lost control → lower
productivity → shortages → more unrest.** A battle raises the losing
region's `devastation` directly (`resolve_battle`). Devastation feeds the
region's unrest target in `tick_unrest`, and unrest above 0.34 (net of
legitimacy) breeds insurgency. Insurgency degrades `region.control`
(`tick_unrest`), and `control` multiplies directly into total factor
productivity (`economy.py:tfp`, `t *= 0.55 + 0.55 * control`) — a region the
state doesn't functionally hold produces less, full stop. Lower output means
less of everything gets made, which shows up nationally as `_shortfall` in
`sim_economy.tick_economy`, and physical shortfall of food, power or medicine
directly raises unrest again in the same tick (`r.unrest = clamp01(r.unrest +
food*0.010 + energy*0.005)`) — closing the loop. The same devastation term
also directly suppresses fertility and raises the death rate
(`tick_population`), so a region caught in this loop for long enough
literally empties out.

**Repression vs. legitimacy → insurgency, twice over.** Unrest feeds
insurgency faster the less legitimate the regime is (`0.4 + 0.9*(1 -
legitimacy)`), and faster still if repression is outrunning legitimacy
specifically (`1 + 1.4*clamp01(control - legitimacy)`), while every
authoritarian-leaning policy response (`policing`, `surveillance`,
`censorship`) is itself pushed *up* automatically once unrest passes 25%.
That is a genuine trap: the mechanical response to unrest raises repression,
which (unless legitimacy keeps pace) accelerates the very insurgency it was
meant to suppress.

**Corruption ⇄ state capacity ⇄ legitimacy.** State capacity's target falls
with corruption; corruption's target falls with state capacity (and with
media freedom, and with policing) but rises with surveillance held against
media freedom; legitimacy's target falls with corruption and rises with
state capacity. All three are mutually reinforcing in both directions —
a state that starts sliding on any one of these tends to slide on all three,
and pulling any one back up (say, by winning an election and boosting
approval) gives the other two room to recover too.

**Debt → credit rating → inflation/unrest → revenue → debt.** A debt ratio
above 1.6 (of annual GDP) pushes the inflation target up; the credit rating
target falls with debt ratio, inflation and unrest; a falling credit rating
raises the effective interest rate nations borrow at (`debt_service` factors
in `w.market.credit_spread + 0.06*(1 - credit_rating)`); higher debt service
crowds out the primary balance, which (when it goes negative for long enough)
raises the debt ratio further. Tax revenue itself is discounted by unrest
(`rev *= 1 - 0.45*nat.unrest`), so a nation whose unrest is already elevated
collects less of the revenue it needs to service the debt that's partly
driving the unrest.

**Climate → disasters → devastation → unrest**, and **war/tension →
doomsday**, run the same shape of loop at planetary scale: emissions from
GDP raise CO2 and temperature anomaly; temperature anomaly raises both the
natural-disaster base rate and the doomsday counter directly; disasters raise
regional devastation and unrest the same way battles do; and world tension
(itself raised by every war, nuclear test, and crisis) adds to doomsday
alongside temperature anomaly, so a world sliding into great-power conflict
and a world sliding into climate crisis push the same terminal counter.

**Information warfare → approval/legitimacy → unrest → coup/election risk.**
A `scandal` or `conspiracy` narrative directly cuts approval and legitimacy
while it's salient; falling legitimacy raises the unrest target and the coup
probability (`coup_p` scales with `1 - army_loyalty` and with unrest) in the
very same daily tick sequence, and depresses the incumbent's expected vote
share the next time `tick_elections` runs a scheduled election. This is the
mechanical basis for `disinfo`, `leak` and `blackmail`-driven leaks as a
route to unseating a government without ever touching its military.

**The player's own heat loop.** Any exposed operation raises heat and
exposure; sustained heat raises pursuit-check probability
(`tick_player:_pursuit`) and slowly raises `notoriety`, which raises the
player's daily overhead burn rate — visibility is expensive in more than one
currency at once, and hiding (which cools heat faster) is also unavailable
time that could have gone to any other action.
