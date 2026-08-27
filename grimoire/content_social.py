"""Political, ideological, and personal content tables."""
from __future__ import annotations

# ---------------------------------------------------------------------------
# Ideology is a 6-axis vector, each in -1..+1.
#   econ    -1 collectivist ......... +1 market
#   social  -1 traditional .......... +1 progressive
#   auth    -1 libertarian .......... +1 authoritarian
#   nation  -1 internationalist ..... +1 nationalist
#   milit   -1 pacifist ............. +1 militarist
#   eco     -1 extractive ........... +1 ecological
# ---------------------------------------------------------------------------
AXES = ["econ", "social", "auth", "nation", "milit", "eco"]
AXIS_LABEL = {
    "econ": ("collectivist", "market"), "social": ("traditional", "progressive"),
    "auth": ("libertarian", "authoritarian"), "nation": ("internationalist", "nationalist"),
    "milit": ("pacifist", "militarist"), "eco": ("extractive", "ecological"),
}

IDEOLOGIES: dict[str, dict] = {
    "social_democracy": dict(v=(-0.35, 0.45, -0.15, -0.20, -0.25, 0.40), appeal="workers"),
    "liberalism":       dict(v=(0.45, 0.45, -0.45, -0.45, -0.15, 0.15), appeal="urban"),
    "conservatism":     dict(v=(0.40, -0.55, 0.25, 0.45, 0.30, -0.25), appeal="rural"),
    "national_populism":dict(v=(0.05, -0.60, 0.55, 0.90, 0.45, -0.35), appeal="left_behind"),
    "socialism":        dict(v=(-0.85, 0.55, 0.10, -0.35, -0.20, 0.35), appeal="workers"),
    "market_radical":   dict(v=(0.95, 0.10, -0.55, -0.10, 0.05, -0.55), appeal="capital"),
    "technocracy":      dict(v=(0.25, 0.35, 0.55, -0.30, 0.10, 0.35), appeal="professional"),
    "theocracy":        dict(v=(-0.05, -0.95, 0.80, 0.45, 0.30, -0.10), appeal="devout"),
    "militarism":       dict(v=(0.10, -0.45, 0.85, 0.75, 0.95, -0.35), appeal="military"),
    "agrarianism":      dict(v=(-0.25, -0.35, -0.10, 0.35, -0.15, 0.55), appeal="rural"),
    "ecologism":        dict(v=(-0.40, 0.60, 0.05, -0.45, -0.55, 0.98), appeal="youth"),
    "anarchism":        dict(v=(-0.55, 0.70, -0.98, -0.70, -0.30, 0.55), appeal="youth"),
    "monarchism":       dict(v=(0.25, -0.75, 0.70, 0.55, 0.35, -0.05), appeal="elite"),
    "corporatism":      dict(v=(0.65, -0.20, 0.55, 0.35, 0.25, -0.40), appeal="capital"),
    "accelerationism":  dict(v=(0.70, 0.65, 0.30, -0.55, 0.20, -0.30), appeal="professional"),
    "syndicalism":      dict(v=(-0.75, 0.40, -0.40, -0.15, 0.05, 0.30), appeal="workers"),
    "reactionism":      dict(v=(0.30, -0.95, 0.65, 0.70, 0.55, -0.45), appeal="devout"),
    "cosmopolitanism":  dict(v=(0.35, 0.70, -0.30, -0.95, -0.45, 0.35), appeal="urban"),
}
IDEOLOGY_LIST = list(IDEOLOGIES)

# Social classes / audiences that opinions are tracked for.
AUDIENCES = ["workers", "rural", "urban", "capital", "professional", "military",
             "devout", "youth", "elite", "left_behind", "minorities", "students"]

GOV_TYPES: dict[str, dict] = {
    "liberal_democracy":  dict(elections=True, repress=0.10, legit_base=0.62, corrupt=0.22,
                               coup_risk=0.02, speed=0.55, desc="Competitive elections, courts with teeth, a press that bites."),
    "flawed_democracy":   dict(elections=True, repress=0.24, legit_base=0.52, corrupt=0.40,
                               coup_risk=0.06, speed=0.65, desc="Elections happen. So does vote-buying."),
    "dominant_party":     dict(elections=True, repress=0.48, legit_base=0.50, corrupt=0.55,
                               coup_risk=0.07, speed=0.80, desc="A ballot with one plausible outcome."),
    "military_junta":     dict(elections=False, repress=0.78, legit_base=0.34, corrupt=0.62,
                               coup_risk=0.16, speed=0.90, desc="Order by decree, enforced by armour."),
    "personalist":        dict(elections=False, repress=0.72, legit_base=0.40, corrupt=0.75,
                               coup_risk=0.13, speed=0.95, desc="The state is a person, and the person is tired."),
    "one_party_state":    dict(elections=False, repress=0.70, legit_base=0.46, corrupt=0.50,
                               coup_risk=0.06, speed=0.88, desc="The Party is the country, the country is the Party."),
    "absolute_monarchy":  dict(elections=False, repress=0.60, legit_base=0.52, corrupt=0.58,
                               coup_risk=0.09, speed=0.85, desc="Divine right, modern accountancy."),
    "const_monarchy":     dict(elections=True, repress=0.14, legit_base=0.66, corrupt=0.26,
                               coup_risk=0.02, speed=0.55, desc="A crown that reigns without ruling."),
    "theocratic_state":   dict(elections=False, repress=0.68, legit_base=0.55, corrupt=0.48,
                               coup_risk=0.08, speed=0.70, desc="Law descends from a higher court."),
    "technocracy":        dict(elections=False, repress=0.45, legit_base=0.53, corrupt=0.30,
                               coup_risk=0.07, speed=0.85, desc="Rule by credential and by model."),
    "corporate_state":    dict(elections=True, repress=0.38, legit_base=0.44, corrupt=0.72,
                               coup_risk=0.06, speed=0.78, desc="Shareholders are the electorate that counts."),
    "failed_state":       dict(elections=False, repress=0.30, legit_base=0.14, corrupt=0.88,
                               coup_risk=0.30, speed=0.25, desc="A flag, a capital, and very little else."),
    "federal_republic":   dict(elections=True, repress=0.16, legit_base=0.60, corrupt=0.30,
                               coup_risk=0.03, speed=0.45, desc="Sovereignty divided, gridlock included."),
    "council_state":      dict(elections=True, repress=0.35, legit_base=0.50, corrupt=0.35,
                               coup_risk=0.09, speed=0.50, desc="Power by assembly, delegate by delegate."),
}
GOV_LIST = list(GOV_TYPES)

# Policy sliders every government maintains (0..1 unless noted).
POLICIES: dict[str, dict] = {
    "tax_income":     dict(lo=0.0, hi=0.7,  default=0.28, label="Income tax"),
    "tax_corporate":  dict(lo=0.0, hi=0.6,  default=0.22, label="Corporate tax"),
    "tax_consumption":dict(lo=0.0, hi=0.4,  default=0.12, label="Consumption tax"),
    "tax_wealth":     dict(lo=0.0, hi=0.1,  default=0.01, label="Wealth tax"),
    "tariff":         dict(lo=0.0, hi=0.6,  default=0.06, label="Average tariff"),
    "welfare":        dict(lo=0.0, hi=1.0,  default=0.35, label="Welfare spending"),
    "healthcare":     dict(lo=0.0, hi=1.0,  default=0.40, label="Healthcare spending"),
    "education":      dict(lo=0.0, hi=1.0,  default=0.42, label="Education spending"),
    "infrastructure": dict(lo=0.0, hi=1.0,  default=0.38, label="Infrastructure"),
    "research":       dict(lo=0.0, hi=1.0,  default=0.30, label="Public R&D"),
    "military":       dict(lo=0.0, hi=1.0,  default=0.28, label="Defence spending"),
    "policing":       dict(lo=0.0, hi=1.0,  default=0.35, label="Policing"),
    "surveillance":   dict(lo=0.0, hi=1.0,  default=0.25, label="Surveillance"),
    "censorship":     dict(lo=0.0, hi=1.0,  default=0.15, label="Censorship"),
    "immigration":    dict(lo=0.0, hi=1.0,  default=0.45, label="Immigration openness"),
    "environment":    dict(lo=0.0, hi=1.0,  default=0.28, label="Environmental regulation"),
    "labour_rights":  dict(lo=0.0, hi=1.0,  default=0.45, label="Labour protections"),
    "market_reg":     dict(lo=0.0, hi=1.0,  default=0.42, label="Market regulation"),
    "capital_control":dict(lo=0.0, hi=1.0,  default=0.18, label="Capital controls"),
    "subsidy_energy": dict(lo=0.0, hi=1.0,  default=0.20, label="Energy subsidy"),
    "subsidy_farm":   dict(lo=0.0, hi=1.0,  default=0.25, label="Agricultural subsidy"),
    "space_program":  dict(lo=0.0, hi=1.0,  default=0.08, label="Space programme"),
    "intel_budget":   dict(lo=0.0, hi=1.0,  default=0.22, label="Intelligence budget"),
    "propaganda":     dict(lo=0.0, hi=1.0,  default=0.18, label="State messaging"),
    "conscription":   dict(lo=0.0, hi=1.0,  default=0.10, label="Conscription"),
}
POLICY_LIST = list(POLICIES)

# Which ideology axis pushes each policy which way.
POLICY_IDEOLOGY = {
    "tax_income": {"econ": -0.55}, "tax_corporate": {"econ": -0.60},
    "tax_wealth": {"econ": -0.50}, "tariff": {"nation": 0.55, "econ": -0.25},
    "welfare": {"econ": -0.65, "social": 0.20}, "healthcare": {"econ": -0.45, "social": 0.25},
    "education": {"social": 0.35, "econ": -0.20}, "research": {"social": 0.25},
    "military": {"milit": 0.85, "nation": 0.30}, "policing": {"auth": 0.55, "social": -0.25},
    "surveillance": {"auth": 0.85}, "censorship": {"auth": 0.80, "social": -0.30},
    "immigration": {"nation": -0.75, "social": 0.35}, "environment": {"eco": 0.90},
    "labour_rights": {"econ": -0.70}, "market_reg": {"econ": -0.75},
    "capital_control": {"econ": -0.50, "nation": 0.40}, "conscription": {"milit": 0.70, "auth": 0.40},
    "propaganda": {"auth": 0.60, "nation": 0.30}, "intel_budget": {"auth": 0.55, "milit": 0.30},
    "space_program": {"nation": 0.25, "milit": 0.20}, "subsidy_farm": {"nation": 0.25, "eco": 0.10},
    "subsidy_energy": {"eco": -0.35}, "tax_consumption": {"econ": 0.25},
    "infrastructure": {"econ": -0.15},
}

# ---------------------------------------------------------------------------
# Character model
# ---------------------------------------------------------------------------
ATTRIBUTES = {
    "intellect":  "Analysis, planning, learning speed",
    "charisma":   "Persuasion, presence, command of a room",
    "will":       "Resolve under stress, resistance to coercion",
    "cunning":    "Deception, misdirection, reading motives",
    "perception": "Noticing what others miss; counter-surveillance",
    "endurance":  "Stamina, health, tolerance for punishment",
    "dexterity":  "Fine motor control, fieldcraft, violence up close",
    "presence":   "Fame-carrying weight; how much a room changes when you enter",
}

SKILLS: dict[str, dict] = {
    # social
    "oratory":       dict(attr="charisma",  cat="social", desc="Move a crowd."),
    "negotiation":   dict(attr="charisma",  cat="social", desc="Close a deal on your terms."),
    "deception":     dict(attr="cunning",   cat="social", desc="Be believed while lying."),
    "intimidation":  dict(attr="will",      cat="social", desc="Make compliance the easy option."),
    "networking":    dict(attr="charisma",  cat="social", desc="Know someone who knows someone."),
    "seduction":     dict(attr="charisma",  cat="social", desc="Leverage attraction and attention."),
    "etiquette":     dict(attr="perception",cat="social", desc="Move through elite spaces unremarked."),
    # power
    "politics":      dict(attr="cunning",   cat="power",  desc="Coalitions, whips, and the art of the vote."),
    "law":           dict(attr="intellect", cat="power",  desc="Statute, loophole, and precedent."),
    "bureaucracy":   dict(attr="intellect", cat="power",  desc="Make the machine move — or jam."),
    "diplomacy":     dict(attr="charisma",  cat="power",  desc="Interests dressed as principle."),
    "propaganda":    dict(attr="cunning",   cat="power",  desc="Author what people believe happened."),
    "command":       dict(attr="presence",  cat="power",  desc="Men and women die on your word."),
    "strategy":      dict(attr="intellect", cat="power",  desc="See three moves past the board."),
    # economic
    "finance":       dict(attr="intellect", cat="econ",   desc="Leverage, arbitrage, and other people's money."),
    "management":    dict(attr="charisma",  cat="econ",   desc="Turn headcount into output."),
    "trade":         dict(attr="cunning",   cat="econ",   desc="Buy the dip in a country's fortunes."),
    "engineering":   dict(attr="intellect", cat="econ",   desc="Build the thing that builds the thing."),
    "logistics":     dict(attr="intellect", cat="econ",   desc="Move mass across distance on schedule."),
    "accounting":    dict(attr="perception",cat="econ",   desc="Hide a river of money in a spreadsheet."),
    # covert
    "tradecraft":    dict(attr="cunning",   cat="covert", desc="Dead drops, covers, and clean exits."),
    "infiltration":  dict(attr="dexterity", cat="covert", desc="Be where you should not be."),
    "hacking":       dict(attr="intellect", cat="covert", desc="Own the machine that owns the record."),
    "surveillance":  dict(attr="perception",cat="covert", desc="Watch without being watched."),
    "forgery":       dict(attr="dexterity", cat="covert", desc="Documents that survive scrutiny."),
    "interrogation": dict(attr="will",      cat="covert", desc="Extract truth, or something like it."),
    "assassination": dict(attr="dexterity", cat="covert", desc="Make a death look like anything else."),
    "smuggling":     dict(attr="cunning",   cat="covert", desc="Freight that isn't on the manifest."),
    # personal
    "medicine":      dict(attr="intellect", cat="self",   desc="Keep bodies working, yours included."),
    "science":       dict(attr="intellect", cat="self",   desc="Push a frontier, publish or bury it."),
    "combat":        dict(attr="dexterity", cat="self",   desc="Survive the two minutes that matter."),
    "survival":      dict(attr="endurance", cat="self",   desc="Weather, wounds, and worse."),
    "theology":      dict(attr="will",      cat="self",   desc="Speak with the authority of the eternal."),
    "arts":          dict(attr="presence",  cat="self",   desc="Make meaning that people repeat."),
    "languages":     dict(attr="intellect", cat="self",   desc="Hear what is said when they think you can't."),
}
SKILL_LIST = list(SKILLS)
SKILL_CATS = ["social", "power", "econ", "covert", "self"]

# Personality traits: mechanical modifiers plus flavour.
TRAITS: dict[str, dict] = {
    "ruthless":      dict(mods={"intimidation": 0.10, "empathy": -0.25}, tags=["dark"]),
    "charming":      dict(mods={"networking": 0.12, "seduction": 0.10}, tags=["light"]),
    "paranoid":      dict(mods={"surveillance": 0.12, "stress_gain": 0.25}, tags=["dark"]),
    "patient":       dict(mods={"stress_gain": -0.20, "strategy": 0.08}, tags=["light"]),
    "reckless":      dict(mods={"risk": 0.30, "combat": 0.08}, tags=["dark"]),
    "meticulous":    dict(mods={"forgery": 0.12, "accounting": 0.10, "speed": -0.10}, tags=["light"]),
    "charismatic":   dict(mods={"oratory": 0.14}, tags=["light"]),
    "vengeful":      dict(mods={"loyalty_decay": 0.15}, tags=["dark"]),
    "loyal":         dict(mods={"betray_chance": -0.40}, tags=["light"]),
    "greedy":        dict(mods={"bribe_taking": 0.35}, tags=["dark"]),
    "ascetic":       dict(mods={"bribe_taking": -0.50, "stress_gain": -0.10}, tags=["light"]),
    "visionary":     dict(mods={"science": 0.10, "propaganda": 0.08}, tags=["light"]),
    "cynical":       dict(mods={"morale_effect": -0.10, "deception": 0.08}, tags=["dark"]),
    "brave":         dict(mods={"combat": 0.10, "fear": -0.30}, tags=["light"]),
    "cowardly":      dict(mods={"fear": 0.35, "combat": -0.10}, tags=["dark"]),
    "workaholic":    dict(mods={"ap": 0.15, "health_decay": 0.12}, tags=["mixed"]),
    "hedonist":      dict(mods={"stress_relief": 0.25, "scandal": 0.25}, tags=["mixed"]),
    "principled":    dict(mods={"legitimacy": 0.10, "deception": -0.15}, tags=["light"]),
    "manipulative":  dict(mods={"deception": 0.14, "trust_decay": 0.10}, tags=["dark"]),
    "stoic":         dict(mods={"will_check": 0.10, "stress_gain": -0.15}, tags=["light"]),
    "erratic":       dict(mods={"variance": 0.40}, tags=["dark"]),
    "magnetic":      dict(mods={"recruit": 0.20}, tags=["light"]),
    "secretive":     dict(mods={"exposure": -0.20, "networking": -0.08}, tags=["mixed"]),
    "ambitious":     dict(mods={"ap": 0.08, "ally_fear": 0.15}, tags=["mixed"]),
    "compassionate": dict(mods={"legitimacy": 0.08, "intimidation": -0.15}, tags=["light"]),
    "obsessive":     dict(mods={"research": 0.15, "stress_gain": 0.20}, tags=["mixed"]),
}
TRAIT_LIST = list(TRAITS)

BACKGROUNDS: dict[str, dict] = {
    "heir": dict(
        label="Dynastic Heir",
        blurb="Old money, older obligations. You inherited a name people already fear.",
        wealth=140_000_000, skills={"etiquette": 0.45, "finance": 0.40, "networking": 0.42, "politics": 0.30},
        attrs={"charisma": 1, "presence": 2}, perks=["old_money", "family_seat"], notoriety=0.18),
    "operative": dict(
        label="Burned Operative",
        blurb="Fifteen years in the field, then a file with your name on it. Now you freelance.",
        wealth=900_000, skills={"tradecraft": 0.62, "infiltration": 0.48, "surveillance": 0.50,
                                "combat": 0.40, "forgery": 0.35, "languages": 0.40},
        attrs={"cunning": 2, "perception": 2, "dexterity": 1}, perks=["ghost_identity", "old_network"], notoriety=0.05),
    "founder": dict(
        label="Tech Founder",
        blurb="You sold the company. The money is real. The itch that made you build it is worse.",
        wealth=48_000_000, skills={"engineering": 0.55, "finance": 0.42, "management": 0.45,
                                   "hacking": 0.38, "science": 0.35},
        attrs={"intellect": 3}, perks=["engineer_mind", "capital_access"], notoriety=0.22),
    "general": dict(
        label="Sidelined General",
        blurb="They gave you a medal and a desk. The army still takes your calls.",
        wealth=2_400_000, skills={"command": 0.66, "strategy": 0.55, "combat": 0.45,
                                  "logistics": 0.42, "intimidation": 0.40},
        attrs={"will": 2, "presence": 2, "endurance": 1}, perks=["officer_corps", "war_college"], notoriety=0.28),
    "demagogue": dict(
        label="Movement Demagogue",
        blurb="You have no office, no army, and eleven million people who repeat what you say.",
        wealth=1_100_000, skills={"oratory": 0.68, "propaganda": 0.55, "politics": 0.45,
                                  "networking": 0.40, "deception": 0.38},
        attrs={"charisma": 3, "presence": 2}, perks=["mass_following", "media_gravity"], notoriety=0.44),
    "banker": dict(
        label="Shadow Banker",
        blurb="You do not own things. You own the debt of everyone who does.",
        wealth=310_000_000, skills={"finance": 0.72, "accounting": 0.58, "trade": 0.50,
                                    "negotiation": 0.45, "law": 0.35},
        attrs={"intellect": 2, "cunning": 2}, perks=["dark_pools", "regulator_friends"], notoriety=0.12),
    "criminal": dict(
        label="Syndicate Underboss",
        blurb="Three ports, two ministers, one bad night that made you boss.",
        wealth=26_000_000, skills={"smuggling": 0.62, "intimidation": 0.55, "networking": 0.45,
                                   "combat": 0.42, "accounting": 0.35, "deception": 0.40},
        attrs={"cunning": 2, "will": 2}, perks=["underworld_ties", "muscle"], notoriety=0.38),
    "scientist": dict(
        label="Heretic Scientist",
        blurb="Your last paper was retracted, classified, then quietly implemented.",
        wealth=420_000, skills={"science": 0.75, "engineering": 0.48, "medicine": 0.42,
                                "hacking": 0.35, "bureaucracy": 0.25},
        attrs={"intellect": 4}, perks=["lab_access", "peer_respect"], notoriety=0.08),
    "cleric": dict(
        label="Schismatic Cleric",
        blurb="You were excommunicated for saying it out loud. Congregations kept growing.",
        wealth=680_000, skills={"theology": 0.70, "oratory": 0.55, "networking": 0.42,
                                "propaganda": 0.40, "etiquette": 0.30},
        attrs={"will": 3, "charisma": 2}, perks=["flock", "sanctuary"], notoriety=0.30),
    "journalist": dict(
        label="Investigative Journalist",
        blurb="You know where eleven bodies are buried. Two of them are metaphors.",
        wealth=180_000, skills={"surveillance": 0.52, "networking": 0.50, "propaganda": 0.45,
                                "deception": 0.35, "languages": 0.38, "law": 0.28},
        attrs={"perception": 3, "intellect": 1}, perks=["sources", "byline"], notoriety=0.20),
    "diplomat": dict(
        label="Career Diplomat",
        blurb="Four postings, three languages, and a very specific understanding of what treaties are for.",
        wealth=1_600_000, skills={"diplomacy": 0.68, "languages": 0.55, "etiquette": 0.50,
                                  "negotiation": 0.48, "politics": 0.38, "bureaucracy": 0.40},
        attrs={"charisma": 2, "intellect": 1, "perception": 1}, perks=["chancery_keys", "immunity"], notoriety=0.14),
    "nobody": dict(
        label="Nobody At All",
        blurb="No file, no fortune, no name worth remembering. That is the entire advantage.",
        wealth=9_000, skills={"survival": 0.35, "deception": 0.25},
        attrs={}, perks=["clean_slate", "underestimated"], notoriety=0.00),
}

PERKS: dict[str, str] = {
    "old_money": "Family capital compounds at +3%/yr and opens elite doors.",
    "family_seat": "A hereditary political seat somewhere in your home nation.",
    "ghost_identity": "One spare legend that heat does not attach to.",
    "old_network": "Start with three placed contacts inside intelligence services.",
    "engineer_mind": "Research projects you personally lead run 25% faster.",
    "capital_access": "Investors will fund your ventures on a handshake.",
    "officer_corps": "Serving officers owe you favours; coup odds improve.",
    "war_college": "Your armies fight above their weight class.",
    "mass_following": "A standing base of supporters that grows with your fame.",
    "media_gravity": "Everything you do is news, for better and worse.",
    "dark_pools": "Move money without leaving a trail regulators can follow.",
    "regulator_friends": "Financial investigations against you stall.",
    "underworld_ties": "Contraband markets, enforcers, and laundries on call.",
    "muscle": "A standing crew of enforcers who will do violence for you.",
    "lab_access": "A laboratory nobody audits.",
    "peer_respect": "Scientists take your calls and share unpublished work.",
    "flock": "Congregations that tithe and turn out.",
    "sanctuary": "Religious premises the state hesitates to raid.",
    "sources": "Secrets surface to you at random.",
    "byline": "You can publish anywhere and be believed.",
    "chancery_keys": "Foreign ministries treat you as one of their own.",
    "immunity": "Diplomatic immunity, until someone bothers to revoke it.",
    "clean_slate": "No file anywhere. Investigations start from nothing.",
    "underestimated": "Rivals systematically misjudge your reach.",
    "cult_of_personality": "Your face alone moves public opinion.",
    "kingmaker": "Heads of state owe their position to you.",
    "deep_pockets": "Bribes cost you 30% less.",
    "iron_stomach": "Ruthless acts cost you less stress and less legitimacy.",
    "quantum_ledger": "Your finances are effectively unauditable.",
    "hand_of_god": "Assassination attempts against you fail more often.",
}

# Relationship dimensions between the player and an NPC.
REL_DIMS = ["trust", "affection", "fear", "respect", "debt"]

FACTION_ROLES = ["head_of_state", "head_of_government", "defence_minister", "finance_minister",
                 "foreign_minister", "interior_minister", "intelligence_chief", "chief_of_staff",
                 "central_banker", "chief_justice", "legislator", "governor", "mayor",
                 "general", "admiral", "air_marshal", "ceo", "banker", "industrialist",
                 "media_baron", "editor", "cleric", "professor", "scientist", "union_boss",
                 "crime_boss", "smuggler", "fixer", "diplomat", "spy", "activist", "celebrity",
                 "athlete", "judge", "prosecutor", "police_chief", "arms_dealer", "lobbyist"]

ROLE_POWER = {
    "head_of_state": 0.95, "head_of_government": 0.90, "intelligence_chief": 0.72,
    "defence_minister": 0.75, "finance_minister": 0.74, "foreign_minister": 0.68,
    "interior_minister": 0.68, "chief_of_staff": 0.60, "central_banker": 0.70,
    "chief_justice": 0.62, "legislator": 0.35, "governor": 0.48, "mayor": 0.34,
    "general": 0.62, "admiral": 0.58, "air_marshal": 0.56, "ceo": 0.58, "banker": 0.55,
    "industrialist": 0.54, "media_baron": 0.60, "editor": 0.38, "cleric": 0.45,
    "professor": 0.28, "scientist": 0.30, "union_boss": 0.42, "crime_boss": 0.48,
    "smuggler": 0.22, "fixer": 0.26, "diplomat": 0.36, "spy": 0.34, "activist": 0.26,
    "celebrity": 0.40, "athlete": 0.28, "judge": 0.40, "prosecutor": 0.42,
    "police_chief": 0.44, "arms_dealer": 0.40, "lobbyist": 0.34,
}

SECRET_KINDS = [
    ("embezzlement", 0.75, "diverted public funds"),
    ("affair", 0.45, "an affair that would end a marriage and a career"),
    ("bribe", 0.70, "took a bribe from a foreign interest"),
    ("false_record", 0.55, "falsified a service record"),
    ("addiction", 0.40, "a dependency they hide from their staff"),
    ("illness", 0.35, "a diagnosis nobody has been told about"),
    ("foreign_asset", 0.90, "has been reporting to a foreign service"),
    ("blood_debt", 0.65, "ordered something that killed civilians"),
    ("plagiarism", 0.30, "built a reputation on stolen work"),
    ("hidden_family", 0.35, "a second family in another country"),
    ("tax_fraud", 0.55, "an offshore structure that is plainly illegal"),
    ("murder", 0.95, "killed someone and buried it"),
    ("cult_ties", 0.50, "belongs to a movement they publicly condemn"),
    ("insider_trading", 0.60, "trades on information they should not have"),
    ("blackmailed", 0.50, "is already being blackmailed by someone else"),
]

NEEDS = ["sleep", "nutrition", "stress", "morale", "vice"]

WOUND_KINDS = [
    ("bruised", 0.05, 6), ("laceration", 0.12, 14), ("concussion", 0.18, 21),
    ("gunshot", 0.35, 60), ("fracture", 0.28, 75), ("burns", 0.30, 90),
    ("stab", 0.30, 45), ("blast", 0.45, 120), ("poisoning", 0.40, 30),
]
