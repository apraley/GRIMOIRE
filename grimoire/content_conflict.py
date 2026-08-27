"""Military, intelligence, crime, health, media and faith content tables."""
from __future__ import annotations

# ---------------------------------------------------------------------------
# Military units.  Costs in credits, upkeep per day, manpower in people.
#   atk/def   base combat factors
#   dom       domain: land, sea, air, space, cyber, nuclear
#   supply    tonnes of upkeep goods per day
# ---------------------------------------------------------------------------
UNITS: dict[str, dict] = {
    "militia":      dict(dom="land", atk=0.30, dfn=0.45, hp=1.0, cost=2.6e7,  up=9e4,  men=4000,
                         supply=0.6, tech=None, build=20, blurb="Rifles and enthusiasm."),
    "infantry":     dict(dom="land", atk=0.70, dfn=0.85, hp=1.0, cost=9.5e7,  up=4.2e5, men=5000,
                         supply=1.0, tech=None, build=45, blurb="The formation that holds ground."),
    "mech_inf":     dict(dom="land", atk=1.00, dfn=1.05, hp=1.3, cost=2.6e8,  up=1.1e6, men=5200,
                         supply=2.2, tech="alloy_metallurgy", build=70, blurb="Infantry that arrives intact."),
    "armour":       dict(dom="land", atk=1.70, dfn=1.15, hp=1.6, cost=4.4e8,  up=1.9e6, men=3800,
                         supply=3.4, tech="alloy_metallurgy", build=90, blurb="Breakthrough, if the fuel holds."),
    "artillery":    dict(dom="land", atk=1.45, dfn=0.55, hp=0.9, cost=2.1e8,  up=1.2e6, men=2600,
                         supply=2.8, tech=None, build=60, blurb="The thing that actually kills people."),
    "rocket_arty":  dict(dom="land", atk=1.95, dfn=0.40, hp=0.8, cost=3.6e8,  up=1.8e6, men=2100,
                         supply=3.6, tech="guided_muni", build=75, blurb="Deep fires with a short conversation."),
    "special_ops":  dict(dom="land", atk=1.25, dfn=0.75, hp=0.7, cost=3.1e8,  up=1.6e6, men=900,
                         supply=0.9, tech=None, build=110, blurb="Raids, sabotage, and deniability."),
    "air_defence":  dict(dom="land", atk=0.25, dfn=1.90, hp=1.0, cost=3.4e8,  up=1.5e6, men=1800,
                         supply=1.6, tech="guided_muni", build=80, blurb="Makes the sky expensive."),
    "engineers":    dict(dom="land", atk=0.25, dfn=0.70, hp=1.0, cost=1.4e8,  up=6e5,  men=3000,
                         supply=1.4, tech=None, build=50, blurb="Bridges, minefields, and fortification."),
    "fighter_wing": dict(dom="air",  atk=1.60, dfn=1.40, hp=0.9, cost=7.2e8,  up=3.4e6, men=1400,
                         supply=3.0, tech="composite_airframe", build=110, blurb="Air superiority or nothing."),
    "strike_wing":  dict(dom="air",  atk=2.20, dfn=0.70, hp=0.8, cost=8.6e8,  up=4.0e6, men=1500,
                         supply=3.8, tech="guided_muni", build=120, blurb="Deep strike against fixed targets."),
    "bomber_wing":  dict(dom="air",  atk=2.90, dfn=0.50, hp=1.0, cost=1.9e9,  up=7.5e6, men=2200,
                         supply=6.0, tech="composite_airframe", build=180, blurb="Strategic bombardment."),
    "transport_air":dict(dom="air",  atk=0.05, dfn=0.30, hp=0.9, cost=4.1e8,  up=2.1e6, men=1100,
                         supply=2.4, tech=None, build=90, blurb="Airlift; the difference between plan and reality."),
    "drone_wing":   dict(dom="air",  atk=1.35, dfn=0.55, hp=0.5, cost=1.6e8,  up=7e5,  men=350,
                         supply=1.0, tech="drone_swarm", build=45, blurb="Cheap, numerous, expendable."),
    "frigate_sqn":  dict(dom="sea",  atk=0.95, dfn=1.20, hp=1.1, cost=5.8e8,  up=2.6e6, men=1600,
                         supply=2.4, tech=None, build=140, blurb="Escort, patrol, and presence."),
    "destroyer_sqn":dict(dom="sea",  atk=1.55, dfn=1.55, hp=1.4, cost=1.4e9,  up=5.4e6, men=2400,
                         supply=3.6, tech="alloy_metallurgy", build=190, blurb="The workhorse of blue water."),
    "sub_flotilla": dict(dom="sea",  atk=2.10, dfn=0.95, hp=1.0, cost=2.2e9,  up=6.8e6, men=900,
                         supply=2.0, tech="alloy_metallurgy", build=230, blurb="The fleet you cannot find."),
    "carrier_grp":  dict(dom="sea",  atk=3.20, dfn=2.20, hp=2.2, cost=1.1e10, up=2.6e7, men=9000,
                         supply=12.0, tech="composite_airframe", build=420, blurb="Sovereignty with a flight deck."),
    "amphib_grp":   dict(dom="sea",  atk=1.10, dfn=1.00, hp=1.3, cost=1.9e9,  up=6.2e6, men=5200,
                         supply=4.5, tech=None, build=210, blurb="Puts an army on a hostile beach."),
    "cyber_cmd":    dict(dom="cyber",atk=1.40, dfn=1.60, hp=0.6, cost=3.2e8,  up=2.4e6, men=1200,
                         supply=0.2, tech="cyber_arsenal", build=70, blurb="Fights in a domain with no front line."),
    "space_cmd":    dict(dom="space",atk=0.90, dfn=1.30, hp=0.8, cost=2.4e9,  up=9.0e6, men=800,
                         supply=0.6, tech="deep_sensors", build=200, blurb="Eyes, timing, and the high ground."),
    "abm_shield":   dict(dom="space",atk=0.10, dfn=3.00, hp=1.2, cost=6.5e9,  up=2.1e7, men=1600,
                         supply=1.2, tech="missile_defence", build=380, blurb="Buys minutes that decide a war."),
    "icbm_field":   dict(dom="nuclear", atk=9.0, dfn=0.10, hp=1.0, cost=3.8e9, up=1.4e7, men=1200,
                         supply=0.8, tech="fission_device", build=300, blurb="The argument that ends arguments."),
    "boomer_sqn":   dict(dom="nuclear", atk=8.0, dfn=1.20, hp=1.4, cost=7.4e9, up=2.4e7, men=1400,
                         supply=1.4, tech="thermonuclear", build=460, blurb="A second strike nobody can pre-empt."),
}
UNIT_LIST = list(UNITS)
DOMAINS = ["land", "sea", "air", "space", "cyber", "nuclear"]

DOCTRINES: dict[str, dict] = {
    "combined_arms":  dict(atk=0.12, dfn=0.08, supply=0.00, morale=0.05,
                           d="Fires, armour and infantry as one instrument."),
    "deep_battle":    dict(atk=0.22, dfn=-0.05, supply=0.10, morale=0.02,
                           d="Strike the rear; collapse the whole depth at once."),
    "defence_indepth":dict(atk=-0.10, dfn=0.28, supply=-0.08, morale=0.08,
                           d="Trade space, bleed the attacker, counter at culmination."),
    "manoeuvre":      dict(atk=0.18, dfn=0.02, supply=0.06, morale=0.10,
                           d="Speed and dislocation over attrition."),
    "attrition":      dict(atk=0.06, dfn=0.16, supply=0.14, morale=-0.05,
                           d="Grind. Whoever runs out of shells first loses."),
    "asymmetric":     dict(atk=0.04, dfn=0.22, supply=-0.20, morale=0.14,
                           d="Refuse the decisive battle; make occupation unaffordable."),
    "shock_terror":   dict(atk=0.26, dfn=-0.12, supply=0.05, morale=-0.15,
                           d="Break will, not lines. Costly in legitimacy."),
    "network_centric":dict(atk=0.16, dfn=0.14, supply=0.02, morale=0.04,
                           d="Sensors to shooters in seconds. Fragile if the mesh drops."),
}

WAR_GOALS = {
    "annex_region":   dict(cost=0.30, escalation=0.65, d="Take and keep a specific region."),
    "regime_change":  dict(cost=0.55, escalation=0.85, d="Replace the government with one of yours."),
    "vassalise":      dict(cost=0.45, escalation=0.70, d="Reduce them to a client state."),
    "resource_grab":  dict(cost=0.25, escalation=0.50, d="Seize named resource concessions."),
    "punitive":       dict(cost=0.15, escalation=0.35, d="Degrade capability, extract concessions, leave."),
    "liberate":       dict(cost=0.30, escalation=0.55, d="Detach a region into independence."),
    "unify":          dict(cost=0.60, escalation=0.90, d="Absorb the whole state."),
    "disarm":         dict(cost=0.28, escalation=0.60, d="Force disarmament and inspections."),
    "reparations":    dict(cost=0.18, escalation=0.40, d="Extract a payment schedule."),
}

# ---------------------------------------------------------------------------
# Intelligence operations
#   risk       base chance of exposure per attempt
#   heat       notoriety/attention generated on exposure
#   skill      which player skill governs it
# ---------------------------------------------------------------------------
OPS: dict[str, dict] = {
    "surveil":       dict(skill="surveillance", risk=0.06, heat=0.02, days=5, cost=2.0e5,
                          d="Build a pattern of life on a target."),
    "recruit_asset": dict(skill="tradecraft", risk=0.14, heat=0.06, days=12, cost=1.2e6,
                          d="Turn an insider into your source."),
    "steal_tech":    dict(skill="hacking", risk=0.22, heat=0.14, days=18, cost=3.5e6,
                          d="Exfiltrate a research programme."),
    "steal_funds":   dict(skill="hacking", risk=0.26, heat=0.20, days=14, cost=1.8e6,
                          d="Move money out of an institution quietly."),
    "sabotage":      dict(skill="infiltration", risk=0.30, heat=0.26, days=16, cost=4.0e6,
                          d="Take an industrial or military asset offline."),
    "blackmail":     dict(skill="tradecraft", risk=0.18, heat=0.16, days=9, cost=8.0e5,
                          d="Convert a secret into obedience."),
    "bribe":         dict(skill="negotiation", risk=0.12, heat=0.10, days=4, cost=0.0,
                          d="Buy a decision outright."),
    "disinfo":       dict(skill="propaganda", risk=0.16, heat=0.12, days=10, cost=2.6e6,
                          d="Push a fabricated narrative into the information space."),
    "assassinate":   dict(skill="assassination", risk=0.42, heat=0.55, days=22, cost=9.0e6,
                          d="Remove a person permanently."),
    "kidnap":        dict(skill="infiltration", risk=0.40, heat=0.48, days=18, cost=6.0e6,
                          d="Take someone off the board and keep them."),
    "coup_prep":     dict(skill="politics", risk=0.34, heat=0.42, days=45, cost=4.2e7,
                          d="Assemble the officers, the broadcaster, and the list."),
    "false_flag":    dict(skill="tradecraft", risk=0.45, heat=0.62, days=30, cost=2.8e7,
                          d="Stage an attack attributed to someone else."),
    "counterintel":  dict(skill="surveillance", risk=0.05, heat=0.02, days=14, cost=2.2e6,
                          d="Hunt for foreign penetration of your own organisation."),
    "cyber_intrude": dict(skill="hacking", risk=0.20, heat=0.15, days=11, cost=2.4e6,
                          d="Pre-position access inside critical infrastructure."),
    "arm_insurgents":dict(skill="smuggling", risk=0.32, heat=0.45, days=35, cost=3.6e7,
                          d="Supply a rebel movement with weapons and money."),
    "extract":       dict(skill="infiltration", risk=0.28, heat=0.22, days=8, cost=3.0e6,
                          d="Pull one of your people out before they are taken."),
    "plant_evidence":dict(skill="forgery", risk=0.24, heat=0.30, days=12, cost=1.6e6,
                          d="Manufacture a paper trail that convicts."),
    "seduce_target": dict(skill="seduction", risk=0.20, heat=0.14, days=16, cost=6.0e5,
                          d="A relationship built entirely as an access route."),
    "leak":          dict(skill="propaganda", risk=0.15, heat=0.20, days=6, cost=3.0e5,
                          d="Give a real secret to a journalist at the right moment."),
    "frame_rival":   dict(skill="deception", risk=0.30, heat=0.34, days=20, cost=5.5e6,
                          d="Make an enemy's downfall look like their own doing."),
}

# ---------------------------------------------------------------------------
# Criminal enterprises
# ---------------------------------------------------------------------------
RACKETS: dict[str, dict] = {
    "smuggling":    dict(margin=0.55, heat=0.10, violence=0.15, cap=1.0, skill="smuggling",
                         d="Untaxed goods across a border that leaks."),
    "protection":   dict(margin=0.70, heat=0.14, violence=0.40, cap=0.5, skill="intimidation",
                         d="A tax on businesses that the state fails to protect."),
    "fraud":        dict(margin=0.62, heat=0.12, violence=0.02, cap=0.9, skill="accounting",
                         d="Invoices, shells, and vanishing counterparties."),
    "cybercrime":   dict(margin=0.68, heat=0.16, violence=0.02, cap=1.2, skill="hacking",
                         d="Ransom, theft, and access resold by the hour."),
    "gunrunning":   dict(margin=0.58, heat=0.28, violence=0.35, cap=1.1, skill="smuggling",
                         d="Small arms into places where they change governments."),
    "counterfeit":  dict(margin=0.52, heat=0.11, violence=0.05, cap=0.8, skill="forgery",
                         d="Goods, documents, and currency that pass at a glance."),
    "laundering":   dict(margin=0.22, heat=0.09, violence=0.03, cap=2.0, skill="finance",
                         d="Wash other people's money for a percentage."),
    "extortion":    dict(margin=0.75, heat=0.22, violence=0.45, cap=0.4, skill="intimidation",
                         d="Leverage applied to individuals with something to lose."),
    "black_market": dict(margin=0.48, heat=0.13, violence=0.12, cap=1.3, skill="trade",
                         d="Sanctioned goods, at sanctioned-goods prices."),
    "bribery_net":  dict(margin=0.35, heat=0.08, violence=0.02, cap=1.5, skill="networking",
                         d="An organised market in official decisions."),
}

HEAT_STAGES = [
    (0.00, "unknown", "No agency has a file with your name on it."),
    (0.15, "noted", "Analysts have flagged a pattern. No name attached yet."),
    (0.32, "watched", "You are a line item in somebody's weekly brief."),
    (0.50, "investigated", "There is an open file, a case officer, and a budget."),
    (0.68, "wanted", "Warrants exist. Travel becomes a calculation."),
    (0.84, "hunted", "Task forces. Standing orders. People looking for you full time."),
    (0.95, "priority_target", "You are a national security priority in more than one capital."),
]

# ---------------------------------------------------------------------------
# Disease registry. SEIR-ish parameters; severity drives mortality.
# ---------------------------------------------------------------------------
DISEASES: dict[str, dict] = {
    "seasonal_flu":  dict(r0=1.18, incub=2, dur=7,  cfr=0.0006, season=0.45, name="Seasonal influenza"),
    "novel_flu":     dict(r0=2.1, incub=3, dur=9,  cfr=0.0085, season=0.35, name="Novel influenza"),
    "respiratory_x": dict(r0=2.9, incub=5, dur=12, cfr=0.0120, season=0.20, name="Respiratory pathogen X"),
    "haemorrhagic":  dict(r0=1.7, incub=8, dur=14, cfr=0.4200, season=0.05, name="Viral haemorrhagic fever"),
    "cholera":       dict(r0=1.9, incub=2, dur=6,  cfr=0.0300, season=0.30, name="Cholera"),
    "measles_r":     dict(r0=8.5, incub=10, dur=8, cfr=0.0025, season=0.25, name="Resurgent measles"),
    "drug_res_tb":   dict(r0=1.05, incub=40, dur=180, cfr=0.0850, season=0.05, name="Drug-resistant tuberculosis"),
    "vector_fever":  dict(r0=1.35, incub=6, dur=10, cfr=0.0016, season=0.60, name="Vector-borne fever"),
    "prion_cluster": dict(r0=0.7, incub=300, dur=120, cfr=0.9500, season=0.00, name="Prion cluster"),
    "engineered":    dict(r0=3.6, incub=6, dur=14, cfr=0.1800, season=0.10, name="Unattributed novel agent"),
}

# ---------------------------------------------------------------------------
# Narrative / meme system: how ideas spread through a population.
# ---------------------------------------------------------------------------
NARRATIVE_KINDS = {
    "scandal":      dict(decay=0.045, virality=0.55, valence=-1, d="A named person did something disqualifying."),
    "conspiracy":   dict(decay=0.012, virality=0.48, valence=-1, d="A hidden hand explains everything."),
    "hero":         dict(decay=0.030, virality=0.42, valence=+1, d="A person is elevated as proof of something."),
    "threat":       dict(decay=0.022, virality=0.62, valence=-1, d="An enemy is coming, and soon."),
    "grievance":    dict(decay=0.010, virality=0.40, valence=-1, d="You were promised better than this."),
    "triumph":      dict(decay=0.035, virality=0.38, valence=+1, d="We did the impossible thing."),
    "panic":        dict(decay=0.060, virality=0.75, valence=-1, d="Get out, get supplies, get your money."),
    "hope":         dict(decay=0.028, virality=0.34, valence=+1, d="It could actually be different."),
    "ridicule":     dict(decay=0.050, virality=0.58, valence=-1, d="They are not dangerous, they are absurd."),
    "martyrdom":    dict(decay=0.008, virality=0.44, valence=+1, d="They died for it, which makes it true."),
    "doctrine":     dict(decay=0.004, virality=0.22, valence=+1, d="A structured worldview, slow and sticky."),
    "denial":       dict(decay=0.026, virality=0.36, valence=+1, d="The reporting is fabricated."),
}

FAITH_DOCTRINES = {
    "ascetic":     dict(v=(-0.3, -0.5, 0.2, 0.0, -0.3, 0.4), spread=0.7, militancy=0.15),
    "evangelical": dict(v=(0.1, -0.6, 0.3, 0.2, 0.2, -0.1), spread=1.5, militancy=0.35),
    "mystical":    dict(v=(-0.2, 0.1, -0.2, -0.3, -0.4, 0.3), spread=0.9, militancy=0.10),
    "orthodox":    dict(v=(0.0, -0.8, 0.4, 0.5, 0.2, 0.0), spread=0.6, militancy=0.25),
    "reformist":   dict(v=(0.1, 0.5, -0.2, -0.2, -0.2, 0.3), spread=1.1, militancy=0.12),
    "militant":    dict(v=(0.0, -0.7, 0.7, 0.7, 0.9, -0.2), spread=1.2, militancy=0.85),
    "syncretic":   dict(v=(0.0, 0.3, -0.1, -0.5, -0.2, 0.2), spread=1.3, militancy=0.08),
    "civic":       dict(v=(0.2, 0.0, 0.3, 0.6, 0.3, 0.0), spread=0.8, militancy=0.20),
}

TREATY_KINDS = {
    "trade":        dict(d="Tariff reduction and market access.", relation=0.10),
    "defence":      dict(d="An attack on one is an attack on all.", relation=0.25),
    "nonaggression":dict(d="Neither party initiates hostilities.", relation=0.12),
    "alliance":     dict(d="Full military and political alignment.", relation=0.32),
    "arms_control": dict(d="Caps and inspections on strategic systems.", relation=0.15),
    "extradition":  dict(d="Fugitives are handed over on request.", relation=0.08),
    "intel_share":  dict(d="Reciprocal access to collection product.", relation=0.18),
    "currency_peg": dict(d="One currency anchors to the other.", relation=0.14),
    "customs_union":dict(d="A shared external tariff wall.", relation=0.22),
    "vassalage":    dict(d="Foreign policy is set in another capital.", relation=0.30),
    "basing":       dict(d="Foreign forces stationed on national soil.", relation=0.20),
    "climate":      dict(d="Binding emissions commitments.", relation=0.10),
}

CRISIS_KINDS = [
    "border_incident", "assassination", "coup_attempt", "financial_panic", "energy_shock",
    "famine", "pandemic", "refugee_surge", "nuclear_test", "cyber_blackout", "sanctions",
    "insurgency", "secession", "corruption_scandal", "election_dispute", "trade_war",
    "naval_standoff", "hostage_crisis", "labour_general_strike", "climate_disaster",
    "space_incident", "ai_incident", "market_crash", "currency_collapse", "terror_attack",
]
