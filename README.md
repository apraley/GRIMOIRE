# GRIMOIRE

GRIMOIRE is a text-based world simulator you play as a single person inside
it. There is no map you control, no faction sheet, no "empire" handed to you
at the start. You generate a planet — plate tectonics, climate, biomes,
resources, then nations, governments, economies, militaries, and several
billion named-in-aggregate people — and you drop one character into it with a
background, a handful of skills, and a bank balance. Everything else is
already running. Governments fall on their own schedule. Markets clear
whether you trade in them or not. Wars start between nations that have never
heard of you. Your job, across however many in-game years you can survive, is
to become load-bearing: to make the simulation unable to describe itself
without describing you.

It is pure Python 3.11, standard library only — no dependencies to install.

## Contents

- [What it feels like to play](#what-it-feels-like-to-play)
- [Running it](#running-it)
- [Quickstart: a first session](#quickstart-a-first-session)
- [The simulated world](#the-simulated-world)
- [The seven victory paths](#the-seven-victory-paths)
- [Commands](#commands)
- [Save format](#save-format)
- [Project layout](#project-layout)
- [Further reading](#further-reading)

## What it feels like to play

You start with three action points a day, a name, and whatever your
background gave you. A Burned Operative starts with three placed contacts
inside foreign intelligence services and nine hundred thousand dollars. A
Dynastic Heir starts with a hereditary seat in the legislature and a hundred
and forty million. A Nobody At All starts with nine thousand dollars, no file
anywhere, and the specific advantage of being beneath anyone's notice. None of
it matters yet. You are one person in a nation of tens of millions, in a world
of nine billion, and the world does not know your name.

The first sessions are small. You `look` around the city you woke up in. You
`meet` a legislator, and either the conversation opens something or it is a
wall and they remember you asked. You `network` a room and come away knowing
six names you didn't before. You `train` a skill, a little, because a
39-year-old former field officer does not become a great orator by wanting
to. You `wait`, and the day turns over: prices move on a shortage you had
nothing to do with, a coup happens in a country you've never visited, a
narrative about a scandal starts circulating and, a week later, dies out
again because nobody kept feeding it.

Then it stops being small. You surveil someone, learn they have a second
family in another country, and now they will do what you ask because the
alternative is worse than compliance — and they will hate you for exactly as
long as they live. You found a company, or a party, or a faith, and for the
first time something in the world has your fingerprints on it permanently.
You run an operation that goes wrong, and a warrant exists somewhere with
your face on it, and for the next several hundred days you are managing heat
instead of ambition. You back a coup and it works, and a nation's army loyalty
just dropped by a third and there is a chairman of the council who owes his
chair to you. You stumble into a war between two great powers because you
sold arms to the wrong side and the disinfo campaign you funded got traced.

By the time any of the seven paths to taking over the world are in reach, you
have stopped being a person doing things to a static backdrop. The backdrop
is doing things back — coups, plagues, market panics, wars you didn't start,
your own liver failing from thirty years of indulging to manage stress — and
your task, unchanged since day one, is still just to spend the day's action
points on the thing that matters most before the world decides for you.

## Running it

```
python3 -m grimoire
```

That starts a fresh game: it builds a new planet, asks you to pick a starting
nation from a shortlist weighted toward the powerful (with a few weak states
mixed in for a harder game), asks you to pick a background, and asks for a
name. Flags:

| Flag | Effect |
|---|---|
| `--seed N` | Use a specific world seed instead of a random one. Same seed, same planet, same nations, same starting choices. |
| `--load NAME` | Resume a save from `~/.grimoire/NAME.grim` instead of starting a new game. |
| `--no-color` | Disable ANSI colour output (also toggleable in-session with `colour off`). |
| `--script FILE` | Read newline-separated commands from `FILE` and run them one at a time (blank lines and lines starting with `#` are skipped), then exit. Useful for scripted playthroughs, regression checks, or setting up a save non-interactively. |

Saves live in `~/.grimoire/*.grim` (gzip-compressed JSON) regardless of which
flags you used to start the session; see [Save format](#save-format).

## Quickstart: a first session

After world generation and character creation, you're looking at a dashboard
and a prompt like:

```
12 Ianus 2049 │ Meridia City │ 3ap │ $900,000 │ ♨0% ❯
```

That's the date, your location, remaining action points today, cash on hand,
and your heat (how much attention intelligence and law enforcement services
are paying you). A first session might go:

```
look
```
Describes where you are: the region's mood, the city's crime level and cost
of living, and the people of consequence physically nearby right now — you
can only `meet` someone who's actually in your region.

```
status
```
The full dashboard: your attributes, skills, relationships, assets, and
progress toward each of the seven victory conditions (all near zero, this
early).

```
network
```
Costs money and an action point, but you spend the evening in a room and come
away having met several people who matter locally — new contacts, a small
trust bump with each.

```
meet Aurelio Vance
```
(Substitute a real name from `look` or `network`'s output.) A longer,
1-action-point read on one person: their role, influence, traits, and — if
your read succeeds — their ambition, loyalty, and whether they're likely to
take a bribe.

```
train oratory
```
Grinds a skill upward. Slower the better you already are, faster with a
higher governing attribute (charisma, for oratory).

```
wait
```
or `wait 5` to fast-forward several days at once. The world advances; you'll
see news, and if anything happens that concerns you directly (an operation of
yours resolves, you're arrested, someone tries to kill you), fast-forwarding
stops early so you don't sleep through it.

From there, the specific path is yours. A representative early arc:

```
found corp | Aurelio Analytics
expand Aurelio Analytics | softworks
surveil Aurelio Vance
blackmail Aurelio Vance
appoint Meridia | Aurelio Vance | finance_minister
```

— charter a company, put capital into a software-house industry, build
leverage on a person of interest, and eventually place them into a cabinet
you didn't have to win an election for. Run `help` at any point for the full
command list, or `help <command>` for one command's usage; `goals` shows your
live progress on all seven victory conditions and what they mean.

## The simulated world

GRIMOIRE's world is not scripted — it is generated once per seed and then
simulated forward one day at a time by roughly a dozen interacting
subsystems. What follows is a summary; [`docs/SYSTEMS.md`](docs/SYSTEMS.md)
goes subsystem by subsystem in depth, including the cross-system feedback
loops (war creates devastation, devastation feeds unrest, unrest feeds
insurgency, insurgency erodes state control, lost control cuts productivity,
lower output creates shortages, shortages feed more unrest — and so on around
several such loops at once).

**Planet generation.** The map is a wrapping (east-west) 160×76 tile
cylindrical grid. Five to seven continental blobs and a scatter of islands
are laid down, then perturbed by layered value noise. Nine to fourteen
tectonic plates are assigned by a Voronoi partition with drift vectors;
convergent plate boundaries raise mountain belts and divergent ones open
trenches, before the elevation field is smoothed. Sea level is calibrated
after the fact to hit a target land fraction (roughly a quarter to a third of
the globe). Climate follows from latitude (a quadratic-in-latitude
temperature band) and altitude (a lapse rate applied above sea level), and
moisture is carried by a genuine orographic model: prevailing winds (trade
winds one way inside 30° and outside 60°, westerlies between) sweep a
moisture "carry" value across each latitude band, mountains wring it out on
the windward side (`rise * 11.0` extra deposition) and starve the leeward
side, and Hadley/Ferrel latitude bands independently scale a base wetness so
you get a genuinely wet equator, dry horse latitudes near 15-25°, wet
mid-latitudes, and dry poles. Rivers are traced downhill from wet highland
sources; coastlines, biomes (thirteen of them, from ice and tundra through
rainforest and desert to ocean and continental shelf), and geologically
clustered resource deposits (iron, copper, oil, lithium, rare earths, and
more) all fall out of the finished elevation/temperature/moisture fields.

**Political geography.** Provinces ("regions") are grown from habitability-
weighted seeds by a randomised breadth-first fill, so shapes are organic
rather than square. Nations are then grown the same way from region seeds,
with target sizes drawn from a Pareto distribution — a world of a few large
powers and many small states, the way real distributions of national size
actually look. Each nation gets a development archetype (advanced,
industrial, emerging, frontier, or extractive) that sets its GDP-per-capita
band, tech level, education, infrastructure and life expectancy; population
is then distributed across regions by carrying capacity (habitability,
arable land, fisheries, coastal access) and a demographic transition applies
(rich nations skew old, poor nations skew young).

**The economy.** Every nation's industry mix is derived, not guessed. Final
demand — household consumption (the anchor: roughly 55% of value), business
investment (~22%), government spending (~18%), and military procurement plus
research (~5% each) — is expanded backward through the recipe table in a
genuine **Leontief input-output** pass: if households want foodstuffs, that
demand pulls grain, which pulls fertilizer and fuel, which pull chemicals and
crude oil, and so on for several rounds until the wave of derived demand
dies out. That physical demand is then apportioned across regions by
suitability (resource endowment, workforce, skill match, infrastructure) and
corrected against each region's actual productivity, so jobs land where they
can really produce rather than uniformly by demand share. Production runs
under two simultaneous constraints: inputs are rationed **nationally** before
anyone produces (so a shortage is shared, not first-come-first-served across
regions), and output is capped by warehouse room under a target stock cover
(otherwise unsellable gluts pile up rather than production idling). Prices
move toward the level that clears local supply and demand, damped and pulled
toward a shared world price; nations trade into a common world buffer stock
subject to trade friction (tariffs, sanctions, war, and a diplomatic-relation
term), and value added rolls up into GDP, tax revenue, government spending,
debt service, inflation and central-bank policy each day.

**Society.** Population dynamics track births (fertility falling with income,
education and urbanisation), deaths (an age-structured hazard, not a flat
crude death rate — a young population dies far more slowly than an old one at
the same life expectancy), ageing between five age bands, and migration
(people move toward safety, jobs and welfare, and away from unrest,
devastation and insurgency). Epidemics run on real **SEIR compartmental
dynamics** — susceptible, exposed, infectious, recovered/dead — with
seasonal forcing, urban-crowding effects on transmission, a healthcare-and-
tech-driven control term, and vaccine development that accelerates once case
counts justify it; new outbreaks seed stochastically, and existing ones
spread along adjacency and (for wealthier nations) air travel links. A ten
named-disease registry ranges from seasonal flu (R0 ~1.2, CFR ~0.06%) to
prion disease and unattributed engineered pathogens. Information spreads as
discrete **narratives** — scandals, conspiracies, threats, triumphs,
grievances — each with a virality and decay rate, that grow in salience per
nation based on connectivity, media freedom, censorship, and how credible
they are, and that measurably move approval, legitimacy, unrest and even a
nation's ideology vector while they're live. Faith adherence drifts with
prosperity and crisis (crisis pushes people toward religion and away from
secularism).

**Power.** Every nation's ideology sits on a **six-axis vector** — economic
(collectivist to market), social (traditional to progressive), authority
(libertarian to authoritarian), national orientation (internationalist to
nationalist), militarism (pacifist to militarist), and ecological
(extractive to ecological) — and eighteen named ideologies (liberalism,
national populism, ecologism, technocracy, and so on) are just reference
points in that same space. Fourteen government types (from liberal democracy
through military junta, theocracy and failed state) each carry base
repression, legitimacy, corruption and coup-risk parameters. Every day,
unrest accumulates from grievance (unemployment, poor health, corruption,
inflation, low legitimacy, war devastation, inequality) net of relief
(welfare, healthcare, growth, legitimacy) and control (repression times state
capacity); sustained unrest against weak legitimacy breeds insurgency, which
degrades territorial control and feeds devastation. Elections run on a
schedule per democracy; coups and revolutions fire stochastically off army
loyalty, unrest and legitimacy; wars are declared when relations, military
balance and ideological appetite line up, fought as a front-by-front
attrition model with terrain and supply-distance modifiers, and can escalate
to nuclear exchange when a losing nuclear power's desperation crosses a
threshold.

**Covert action.** Every intelligence operation — surveillance, recruitment,
blackmail, sabotage, assassination, coups, disinformation, false flags — runs
through the same difficulty/skill/exposure model, whether the actor is you or
a national intelligence service quietly running the same kind of operation
against a rival on its own initiative every day. Difficulty depends on the
target's protection, a defending nation's intelligence capacity and
surveillance policy, and (for organisations) their secrecy. A resolved
operation checks skill against difficulty for success and, independently, an
exposure roll that scales with the operation's inherent risk; an exposed
operation against you raises your heat and, if attribution succeeds, gets
you formally wanted by that nation and starts the pursuit clock.

**You.** You run on the same primitives as everyone else — attributes,
skills, an ideology vector, secrets that can be discovered — plus a set of
mechanics unique to being the player: action points per day (nominally three,
scaled by health, stress and traits), heat and exposure that decay slowly on
their own and faster in hiding, money with a dirty/clean split that laundering
addresses, and a personal survival loop (health, wounds, addictions, sleep,
nutrition) that can kill you as surely as a rival can.

## The seven victory paths

Run `goals` at any time to see your live progress toward each of these
(scored 0-1; reaching 1.0 on any one ends the game in your favour).

| Path | What it takes |
|---|---|
| **Conquest** | Rule, directly or through vassals and puppets, effective control of the majority of the world's population. |
| **Hegemony** | Bind a large enough share of the great powers' combined economic weight into alignment with you — through direct control, puppet states, or the influence of organisations you own inside them. |
| **Capital** | Own so much of world output through equity holdings that sovereignty becomes a formality — roughly a third of global GDP in owned corporate revenue. |
| **Creed** | Convert a large enough share of the species to a faith or movement you founded, personally, from nothing. |
| **Deep State** | Own the people who own the states, without ever holding an office worth naming — a majority of the world's real decision-making power, weighted by each nation's GDP and military strength, held through blackmail, debt, fear, or outright ownership of its leadership. |
| **Singularity** | Complete the Singularity Engine megaproject and hold a commanding lead in privately-known technology — the thing that makes every other path irrelevant. |
| **Apotheosis** | Advance far enough along at least three of the other six paths simultaneously that no single lever anyone could pull would stop you. |

The game also ends — badly — on your own death (violence, illness, wounds
mismanaged for too long), imprisonment you don't survive, or a doomsday
counter (climate change, nuclear war, engineered pandemics all push it)
reaching its ceiling and taking everyone with it. See
[`docs/PLAYING.md`](docs/PLAYING.md) for a proper strategy guide to each
path, what opening moves suit which background, and the common ways players
actually lose.

## Commands

Every action costs a fixed number of action points (AP) out of your daily
budget, and sometimes money up front; screens (map, status, dossiers, and so
on) are free and don't advance time. This is a representative subset —
`help` in-session lists everything, and `help <command>` gives full usage for
one command.

### Screens (free)

| Command | Aliases | Shows |
|---|---|---|
| `status` | `dash`, `st` | Full player dashboard |
| `look` | `where`, `l` | Your immediate surroundings and who's nearby |
| `map [key]` | | World map (`political`, `terrain`, `climate`, `population`, `resource:<kind>`) |
| `news [days] [category]` | | Recent world news |
| `market [good]` | `prices` | World/national commodity prices |
| `wars` | | Active wars |
| `powers [metric]` | `rank` | Nation rankings |
| `intel` | | Your operations, assets and heat |
| `ledger` | `money` | Your financial history |
| `goals` | `victory` | Progress on all seven victory paths |
| `skills` | | Your skill levels |
| `timeline` | | Your personal history |
| `people [filter]` | | People you know or have dealings with |
| `tech [nation]` | `research` | A nation's technology and research focus |
| `nation [name]` | `country` | A nation's full profile |
| `who <name>` | `person`, `dossier` | A person's full profile |
| `region <name>` | `province` | A region's profile |
| `city <name>` | | A city's profile |
| `org <name>` | `company`, `firm` | An organisation's profile |
| `help [command]` | `?`, `actions` | Command list or usage for one command |

### Time and saves

| Command | Effect |
|---|---|
| `wait [n]` | `next`, `end`, `n`, `w` — advance one or more days |
| `save [name]` | Save (default name `auto`) |
| `load [name]` | Load a save |
| `saves` | `list` — list saves |
| `quit` | `exit`, `q` — autosave and leave |

### Personal, social, media (1 AP unless noted)

| Command | Aliases | Effect |
|---|---|---|
| `travel <place>` | `go`, `fly` | Move to a city, region or nation; distance costs days |
| `rest` | `sleep` | Recover stress, health, sleep, nutrition |
| `train <skill>` | | Grind a skill upward |
| `treat` | `doctor`, `hospital` | Buy medical treatment (money) |
| `hide` | `lay_low`, `ground` | Go to ground; heat falls faster |
| `surface` | | Stop hiding |
| `identity [switch n]` | `legend`, `alias` | Build or switch to a clean identity (money) |
| `study <tech>` | `read` | Research a technology personally |
| `meet <person>` | `talk`, `approach` | Read a person; may reveal a secret |
| `cultivate <person>` | `befriend`, `charm` | Build trust and affection (money) |
| `persuade <person> \| <ask>` | `convince` | Argue someone into alignment |
| `threaten <person>` | `intimidate` | Coerce through fear |
| `recruit <person>` | `hire` (2 AP) | Bring someone into your organisation |
| `favour <person> \| <ask>` | `favor`, `call_in` | Spend accumulated leverage |
| `network` | | Meet whoever matters locally (money) |
| `speech <theme>` | `rally`, `address` (2 AP) | Move public opinion (money) |
| `preach [theme]` | | Grow a faith or movement you founded (money) |
| `disinfo <nation> \| <story>` | `smear`, `propaganda` | Seed a fabricated narrative |

### Covert operations (mostly 1-3 AP, most cost money on launch)

| Command | Aliases | Target |
|---|---|---|
| `surveil <target>` | `watch` | Build a pattern of life |
| `recruit_asset <target>` | `turn` (2 AP) | Turn an insider |
| `blackmail <person>` | | Convert a known secret into leverage |
| `bribe <person> \| <amount>` | | Buy a decision outright |
| `rob <target>` | `steal` | Move money out quietly |
| `assassinate <person>` | `kill` (2 AP) | Remove someone permanently |
| `kidnap <person>` | (2 AP) | Take someone off the board |
| `seduce <person>` | | Build access through a relationship |
| `leak <target>` | | Give a secret to a journalist |
| `frame <person>` | (2 AP) | Pin your work on someone else |
| `plant <person>` | | Manufacture a false secret |
| `extract <person>` | | Pull an asset out before capture |
| `steal_tech <nation>` | `espionage` | Exfiltrate a research programme |
| `hack <nation>` | | Cyber access to infrastructure |
| `sabotage <region>` | | Take a facility offline |
| `arm_rebels <region>` | (2 AP) | Fund an insurgency |
| `counterintel <nation>` | `sweep` | Hunt penetration of your own org |
| `false_flag <victim> \| <blame>` | (3 AP) | Stage an attack, attribute it elsewhere |
| `coup <nation> [\| figurehead]` | (3 AP) | Prepare and attempt a coup |

### Economic (1-2 AP)

| Command | Aliases | Effect |
|---|---|---|
| `found <kind> \| <name>` | `charter` (2 AP) | Charter a corp/bank/party/faith/syndicate/media/movement/agency/NGO |
| `expand <org> \| <industry> [\| amount]` | | Invest in an industry through your org |
| `invest <org> \| <amount>` | | Buy equity in a listed company |
| `divest <org> [\| fraction]` | `sell` | Liquidate a holding |
| `acquire <org>` | `takeover` (2 AP) | Buy an organisation outright |
| `launder [amount]` | | Wash dirty money |
| `racket <syndicate> \| <kind>` | | Open a criminal line of business |
| `corner <good> \| <amount>` | (2 AP) | Buy a commodity heavily enough to move its price |
| `unwind <good>` | | Liquidate a commodity position |
| `donate <target> \| <amount>` | | Give money for goodwill or support |

### Political, military, research (1-3 AP)

| Command | Aliases | Effect |
|---|---|---|
| `stand <office>` | `run`, `campaign` (2 AP, money) | Contest an election or vacancy |
| `policy <nation> \| <lever> \| <value>` | | Move a policy slider, if you have authority |
| `purge <nation> \| <person>` | (2 AP) | Remove an official through state machinery |
| `appoint <nation> \| <person> \| <role>` | | Put your person into a ministry |
| `decree <nation> \| <what>` | (2 AP) | Rule by fiat |
| `mobilise <nation>` | `mobilize` | Call up reserves, war footing |
| `declare_war <a> \| <b> \| <goal>` | `war` (3 AP) | Commit a nation you control to war |
| `peace <war>` | (2 AP) | End a war you have standing to end |
| `treaty <a> \| <b> \| <kind>` | | Broker an agreement |
| `sanction <by> \| <target>` | | Cut a state out of the world economy |
| `fund_research <target> \| <amount>` | | Push money into a research programme |
| `project [name]` | (2 AP) | Begin (or list) a personal megaproject |
| `invest_project <name> \| <amount>` | | Fund a megaproject to completion |

## Save format

`save [name]` (default name `auto`) serialises the entire `World` object
graph — every region, nation, person, organisation, war, epidemic, narrative,
market history, and the player themselves — to
`~/.grimoire/<name>.grim`. The format is a small generic object graph
encoder (`grimoire/serial.py`): classes opt in with a `@serializable`
decorator, and the encoder walks `__dict__` (or `__getstate__` where an
object defines one) recursively, tagging sets, tuples, deques and dict
subclasses so they round-trip exactly rather than degrading to plain
lists/dicts. The result is JSON, gzip-compressed at level 6. A `SAVE_VERSION`
constant is embedded in every save and checked strictly on load — a save
written by a different version of the format refuses to load rather than
silently loading wrong. `saves` (or `list`) enumerates what's in
`~/.grimoire/`, and `load <name>` restores everything, including the
per-subsystem random number streams (see `grimoire/rng.py`), so a resumed
game continues exactly where it left off rather than merely restoring the
same starting conditions. Quitting normally (`quit`/`exit`/`q`) autosaves to
`auto` first.

## Project layout

```
grimoire/
  __main__.py        entry point, argument parsing
  shell.py            interactive REPL, screens, save/load, character creation
  actions.py           the action registry: every command the player can invoke
  player.py            the Player/Person model, daily player upkeep tick
  victory.py            the seven victory paths and their scoring
  views.py               dashboard, map, and every other information screen
  entities.py            core entities: City, Region, Nation, Person, Org, War, ...
  world.py                the World container, global market, news log
  engine.py                the daily tick loop: the order every subsystem runs in
  worldgen.py            world generation: regions, nations, population, economy seed
  worldgen_social.py      world generation: politics, faiths, people, institutions
  worldmap.py             planet generation: tectonics, climate, biomes, rivers
  economy.py              production, prices, trade, national accounts
  io_balance.py           the Leontief input-output demand/jobs solver
  sim_economy.py           daily economic tick: production, trade, firms, labour
  sim_society.py           population, health/epidemics, migration, media, faith
  sim_power.py             politics, unrest, coups, elections, diplomacy, war
  sim_world.py             research, environment, disasters, individual agency
  sim_covert.py             intelligence operations, counter-intel, organised crime
  content_econ.py           goods, industry recipes, biomes (static data)
  content_social.py         ideology, government, skills, backgrounds (static data)
  content_conflict.py       units, doctrines, ops, diseases, treaties (static data)
  content_tech.py           the technology tree (static data)
  rng.py                    deterministic, stream-separated random number generation
  serial.py                 generic save/load
  gametime.py                 the game calendar
  names.py, ui.py, util.py     procedural naming, terminal rendering, small helpers
docs/
  SYSTEMS.md              deep technical tour of every simulated subsystem
  PLAYING.md              strategy guide: backgrounds, AP, heat, leverage, money
  CONTENT.md              generated reference tables for all static content
  gen_tables.py           the script that generates CONTENT.md from the source
```

## Further reading

- [`docs/SYSTEMS.md`](docs/SYSTEMS.md) — what state each subsystem holds,
  what its daily tick does, and the feedback loops that connect them.
- [`docs/PLAYING.md`](docs/PLAYING.md) — a strategy guide: the twelve
  backgrounds, action-point economy, managing heat and pursuit, building
  leverage on people, money and how to make it, which victory path suits
  which opening, and the common ways games actually end.
- [`docs/CONTENT.md`](docs/CONTENT.md) — every commodity, industry recipe,
  technology, military unit, intelligence operation, government type,
  ideology, skill and background, generated directly from source.
