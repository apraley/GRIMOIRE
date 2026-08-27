"""Economic content tables: goods, production recipes, resources, biomes."""
from __future__ import annotations

# ---------------------------------------------------------------------------
# Commodity registry.
#   tier      0 raw, 1 refined, 2 manufactured, 3 advanced/strategic
#   base      reference price per unit in credits
#   elast     price elasticity of demand (higher = more responsive)
#   perish    fraction of stock lost per day
#   strat     strategic weight (drives sanctions, war goals, chokepoints)
#   bulk      shipping cost multiplier
# ---------------------------------------------------------------------------
GOODS: dict[str, dict] = {
    # --- agriculture & food -------------------------------------------------
    "grain":        dict(tier=0, base=200,   elast=0.35, perish=0.004, strat=0.75, bulk=1.3, cat="food"),
    "produce":      dict(tier=0, base=380,   elast=0.55, perish=0.030, strat=0.35, bulk=1.6, cat="food"),
    "livestock":    dict(tier=0, base=900,   elast=0.60, perish=0.006, strat=0.30, bulk=1.8, cat="food"),
    "fish":         dict(tier=0, base=700,   elast=0.55, perish=0.040, strat=0.30, bulk=1.7, cat="food"),
    "foodstuffs":   dict(tier=1, base=780,   elast=0.40, perish=0.008, strat=0.70, bulk=1.2, cat="food"),
    "coffee":       dict(tier=1, base=1400,  elast=0.85, perish=0.003, strat=0.10, bulk=1.0, cat="food"),
    "spirits":      dict(tier=2, base=2100,  elast=0.95, perish=0.000, strat=0.05, bulk=1.1, cat="food"),
    "fertilizer":   dict(tier=1, base=560,   elast=0.30, perish=0.001, strat=0.65, bulk=1.3, cat="chem"),
    # --- energy -------------------------------------------------------------
    "crude":        dict(tier=0, base=620,   elast=0.25, perish=0.000, strat=1.00, bulk=1.1, cat="energy"),
    "gas":          dict(tier=0, base=430,   elast=0.30, perish=0.002, strat=0.90, bulk=1.5, cat="energy"),
    "coal":         dict(tier=0, base=180,   elast=0.30, perish=0.000, strat=0.55, bulk=1.6, cat="energy"),
    "uranium":      dict(tier=0, base=9500,  elast=0.15, perish=0.000, strat=1.00, bulk=0.7, cat="energy"),
    "fuel":         dict(tier=1, base=980,   elast=0.30, perish=0.001, strat=0.95, bulk=1.1, cat="energy"),
    "power":        dict(tier=1, base=520,   elast=0.25, perish=1.000, strat=0.90, bulk=0.0, cat="energy"),
    # --- minerals & materials ----------------------------------------------
    "iron":         dict(tier=0, base=210,   elast=0.30, perish=0.000, strat=0.70, bulk=1.7, cat="mineral"),
    "copper":       dict(tier=0, base=1450,  elast=0.35, perish=0.000, strat=0.75, bulk=1.2, cat="mineral"),
    "bauxite":      dict(tier=0, base=310,   elast=0.30, perish=0.000, strat=0.50, bulk=1.6, cat="mineral"),
    "lithium":      dict(tier=0, base=4200,  elast=0.40, perish=0.000, strat=0.90, bulk=1.0, cat="mineral"),
    "rare_earth":   dict(tier=0, base=8800,  elast=0.25, perish=0.000, strat=1.00, bulk=0.8, cat="mineral"),
    "gold":         dict(tier=0, base=61000, elast=0.60, perish=0.000, strat=0.45, bulk=0.4, cat="mineral"),
    "gems":         dict(tier=0, base=42000, elast=1.10, perish=0.000, strat=0.20, bulk=0.3, cat="mineral"),
    "timber":       dict(tier=0, base=170,   elast=0.40, perish=0.001, strat=0.25, bulk=1.9, cat="mineral"),
    "steel":        dict(tier=1, base=690,   elast=0.35, perish=0.000, strat=0.85, bulk=1.5, cat="material"),
    "alloys":       dict(tier=1, base=2300,  elast=0.35, perish=0.000, strat=0.90, bulk=1.1, cat="material"),
    "cement":       dict(tier=1, base=140,   elast=0.30, perish=0.002, strat=0.35, bulk=2.0, cat="material"),
    "plastics":     dict(tier=1, base=880,   elast=0.45, perish=0.000, strat=0.45, bulk=1.2, cat="material"),
    "chemicals":    dict(tier=1, base=1250,  elast=0.40, perish=0.001, strat=0.65, bulk=1.2, cat="chem"),
    "glass":        dict(tier=1, base=420,   elast=0.45, perish=0.000, strat=0.20, bulk=1.5, cat="material"),
    "textiles":     dict(tier=1, base=760,   elast=0.70, perish=0.001, strat=0.20, bulk=1.1, cat="consumer"),
    # --- manufactured -------------------------------------------------------
    "machinery":    dict(tier=2, base=5400,  elast=0.45, perish=0.000, strat=0.70, bulk=1.3, cat="industry"),
    "vehicles":     dict(tier=2, base=9800,  elast=0.75, perish=0.001, strat=0.45, bulk=1.4, cat="consumer"),
    "electronics":  dict(tier=2, base=7600,  elast=0.65, perish=0.002, strat=0.80, bulk=0.7, cat="tech"),
    "semis":        dict(tier=3, base=31000, elast=0.30, perish=0.001, strat=1.00, bulk=0.4, cat="tech"),
    "pharma":       dict(tier=2, base=12500, elast=0.25, perish=0.004, strat=0.80, bulk=0.6, cat="health"),
    "medtech":      dict(tier=3, base=24000, elast=0.30, perish=0.001, strat=0.60, bulk=0.6, cat="health"),
    "aircraft":     dict(tier=3, base=88000, elast=0.55, perish=0.000, strat=0.85, bulk=1.2, cat="industry"),
    "ships":        dict(tier=3, base=76000, elast=0.50, perish=0.000, strat=0.80, bulk=2.2, cat="industry"),
    "arms":         dict(tier=3, base=27000, elast=0.35, perish=0.000, strat=1.00, bulk=1.2, cat="military"),
    "munitions":    dict(tier=2, base=3100,  elast=0.30, perish=0.001, strat=0.95, bulk=1.4, cat="military"),
    "luxury":       dict(tier=2, base=19000, elast=1.40, perish=0.000, strat=0.05, bulk=0.8, cat="consumer"),
    "robotics":     dict(tier=3, base=42000, elast=0.45, perish=0.001, strat=0.90, bulk=0.8, cat="tech"),
    "satellites":   dict(tier=3, base=210000,elast=0.35, perish=0.000, strat=0.95, bulk=0.9, cat="space"),
    "compute":      dict(tier=3, base=15000, elast=0.35, perish=0.010, strat=1.00, bulk=0.2, cat="tech"),
    # --- services & intangibles --------------------------------------------
    "software":     dict(tier=3, base=6800,  elast=0.55, perish=0.006, strat=0.70, bulk=0.0, cat="tech"),
    "media":        dict(tier=2, base=2400,  elast=1.20, perish=0.030, strat=0.45, bulk=0.0, cat="culture"),
    "finance":      dict(tier=2, base=4100,  elast=0.85, perish=0.020, strat=0.60, bulk=0.0, cat="service"),
    "logistics":    dict(tier=2, base=1600,  elast=0.40, perish=0.050, strat=0.70, bulk=0.0, cat="service"),
    "contraband":   dict(tier=2, base=34000, elast=0.90, perish=0.010, strat=0.30, bulk=0.5, cat="illicit"),
}

GOOD_LIST = list(GOODS)
FOOD_GOODS = [g for g, d in GOODS.items() if d["cat"] == "food"]
STRATEGIC = [g for g, d in GOODS.items() if d["strat"] >= 0.85]

# ---------------------------------------------------------------------------
# Industries: input recipe -> output.  `labor` is workers per unit of output
# per day, `capital` is capital stock required, `skill` is the education level
# demanded, `dirty` drives pollution, `tech` names a gating technology.
# ---------------------------------------------------------------------------
INDUSTRIES: dict[str, dict] = {
    "farming":      dict(out="grain", per=1.0, inp={"fertilizer": 0.05, "fuel": 0.03},
                         labor=0.9, capital=0.5, skill=0.15, dirty=0.20, land=1.0, tech=None),
    "orchards":     dict(out="produce", per=1.0, inp={"fertilizer": 0.06, "fuel": 0.03},
                         labor=1.1, capital=0.5, skill=0.18, dirty=0.15, land=0.8, tech=None),
    "ranching":     dict(out="livestock", per=1.0, inp={"grain": 0.45, "fuel": 0.04},
                         labor=0.7, capital=0.6, skill=0.18, dirty=0.45, land=2.2, tech=None),
    "fishing":      dict(out="fish", per=1.0, inp={"fuel": 0.10},
                         labor=0.8, capital=0.9, skill=0.22, dirty=0.20, land=0.0, tech=None),
    "food_proc":    dict(out="foodstuffs", per=1.0, inp={"grain": 0.5, "produce": 0.2,
                                                         "livestock": 0.15, "power": 0.08},
                         labor=0.5, capital=1.1, skill=0.30, dirty=0.20, land=0.1, tech=None),
    "mining_iron":  dict(out="iron", per=1.0, inp={"fuel": 0.08, "machinery": 0.004},
                         labor=0.6, capital=1.4, skill=0.25, dirty=0.60, land=0.3, tech=None),
    "mining_cu":    dict(out="copper", per=1.0, inp={"fuel": 0.10, "power": 0.06},
                         labor=0.6, capital=1.6, skill=0.28, dirty=0.65, land=0.3, tech=None),
    "mining_bx":    dict(out="bauxite", per=1.0, inp={"fuel": 0.09},
                         labor=0.5, capital=1.3, skill=0.24, dirty=0.60, land=0.3, tech=None),
    "mining_li":    dict(out="lithium", per=1.0, inp={"power": 0.15, "chemicals": 0.05},
                         labor=0.4, capital=2.0, skill=0.40, dirty=0.55, land=0.3, tech="brine_extraction"),
    "mining_re":    dict(out="rare_earth", per=1.0, inp={"chemicals": 0.12, "power": 0.18},
                         labor=0.5, capital=2.4, skill=0.45, dirty=0.85, land=0.3, tech="rare_separation"),
    "mining_au":    dict(out="gold", per=1.0, inp={"chemicals": 0.08, "power": 0.10},
                         labor=0.7, capital=1.8, skill=0.30, dirty=0.70, land=0.2, tech=None),
    "gemworks":     dict(out="gems", per=1.0, inp={"power": 0.05},
                         labor=0.9, capital=1.0, skill=0.35, dirty=0.35, land=0.2, tech=None),
    "uranium_mine": dict(out="uranium", per=1.0, inp={"chemicals": 0.15, "power": 0.20},
                         labor=0.5, capital=2.6, skill=0.55, dirty=0.90, land=0.2, tech="isotope_sep"),
    "forestry":     dict(out="timber", per=1.0, inp={"fuel": 0.05},
                         labor=0.7, capital=0.6, skill=0.15, dirty=0.40, land=1.6, tech=None),
    "oil_extract":  dict(out="crude", per=1.0, inp={"machinery": 0.006, "power": 0.05},
                         labor=0.3, capital=2.2, skill=0.35, dirty=0.75, land=0.2, tech=None),
    "gas_extract":  dict(out="gas", per=1.0, inp={"machinery": 0.005, "power": 0.04},
                         labor=0.25, capital=2.0, skill=0.35, dirty=0.60, land=0.2, tech=None),
    "coal_mine":    dict(out="coal", per=1.0, inp={"machinery": 0.003},
                         labor=0.8, capital=0.9, skill=0.18, dirty=0.95, land=0.3, tech=None),
    "refining":     dict(out="fuel", per=1.0, inp={"crude": 0.9, "power": 0.10},
                         labor=0.2, capital=2.4, skill=0.45, dirty=0.80, land=0.1, tech=None),
    "power_fossil": dict(out="power", per=1.0, inp={"coal": 0.35, "gas": 0.20},
                         labor=0.15, capital=2.0, skill=0.40, dirty=1.00, land=0.1, tech=None),
    "power_nuclear":dict(out="power", per=1.0, inp={"uranium": 0.004},
                         labor=0.20, capital=4.2, skill=0.70, dirty=0.10, land=0.1, tech="fission_gen3"),
    "power_solar":  dict(out="power", per=1.0, inp={"semis": 0.0008},
                         labor=0.08, capital=2.6, skill=0.45, dirty=0.03, land=0.6, tech="pv_thinfilm"),
    "power_wind":   dict(out="power", per=1.0, inp={"alloys": 0.002},
                         labor=0.08, capital=2.4, skill=0.45, dirty=0.03, land=0.5, tech="turbine_offshore"),
    "power_fusion": dict(out="power", per=1.0, inp={"alloys": 0.004, "compute": 0.0006},
                         labor=0.10, capital=7.0, skill=0.90, dirty=0.01, land=0.2, tech="fusion_ignition"),
    "steelworks":   dict(out="steel", per=1.0, inp={"iron": 0.85, "coal": 0.30, "power": 0.20},
                         labor=0.35, capital=2.0, skill=0.38, dirty=0.90, land=0.1, tech=None),
    "alloyworks":   dict(out="alloys", per=1.0, inp={"steel": 0.5, "copper": 0.15,
                                                     "rare_earth": 0.02, "power": 0.25},
                         labor=0.30, capital=2.6, skill=0.55, dirty=0.65, land=0.1, tech="alloy_metallurgy"),
    "cementworks":  dict(out="cement", per=1.0, inp={"power": 0.20, "coal": 0.15},
                         labor=0.30, capital=1.2, skill=0.22, dirty=0.95, land=0.1, tech=None),
    "chemworks":    dict(out="chemicals", per=1.0, inp={"crude": 0.25, "gas": 0.20, "power": 0.18},
                         labor=0.28, capital=2.2, skill=0.50, dirty=0.85, land=0.1, tech=None),
    "fertplant":    dict(out="fertilizer", per=1.0, inp={"gas": 0.35, "chemicals": 0.10, "power": 0.12},
                         labor=0.22, capital=1.6, skill=0.40, dirty=0.70, land=0.1, tech=None),
    "plasticworks": dict(out="plastics", per=1.0, inp={"chemicals": 0.55, "power": 0.10},
                         labor=0.25, capital=1.4, skill=0.35, dirty=0.60, land=0.1, tech=None),
    "glassworks":   dict(out="glass", per=1.0, inp={"power": 0.22},
                         labor=0.30, capital=1.1, skill=0.28, dirty=0.45, land=0.1, tech=None),
    "millworks":    dict(out="textiles", per=1.0, inp={"chemicals": 0.10, "power": 0.08},
                         labor=1.2, capital=0.8, skill=0.20, dirty=0.40, land=0.1, tech=None),
    "machineshops": dict(out="machinery", per=1.0, inp={"steel": 0.45, "alloys": 0.10,
                                                        "electronics": 0.04, "power": 0.15},
                         labor=0.45, capital=2.0, skill=0.55, dirty=0.35, land=0.1, tech=None),
    "autoworks":    dict(out="vehicles", per=1.0, inp={"steel": 0.40, "plastics": 0.12,
                                                       "electronics": 0.10, "machinery": 0.05, "power": 0.14},
                         labor=0.50, capital=2.4, skill=0.50, dirty=0.40, land=0.1, tech=None),
    "electroworks": dict(out="electronics", per=1.0, inp={"semis": 0.06, "copper": 0.08,
                                                          "plastics": 0.10, "power": 0.12},
                         labor=0.45, capital=2.2, skill=0.62, dirty=0.35, land=0.1, tech=None),
    "fabs":         dict(out="semis", per=1.0, inp={"chemicals": 0.20, "rare_earth": 0.03,
                                                    "power": 0.55, "machinery": 0.03},
                         labor=0.30, capital=6.5, skill=0.88, dirty=0.30, land=0.1, tech="euv_litho"),
    "datacenters":  dict(out="compute", per=1.0, inp={"semis": 0.10, "power": 0.70},
                         labor=0.12, capital=4.0, skill=0.75, dirty=0.20, land=0.1, tech="hyperscale"),
    "softworks":    dict(out="software", per=1.0, inp={"compute": 0.08},
                         labor=0.85, capital=0.5, skill=0.85, dirty=0.02, land=0.0, tech=None),
    "pharmaworks":  dict(out="pharma", per=1.0, inp={"chemicals": 0.30, "power": 0.10},
                         labor=0.40, capital=3.0, skill=0.80, dirty=0.35, land=0.1, tech=None),
    "medtechworks": dict(out="medtech", per=1.0, inp={"electronics": 0.20, "alloys": 0.10,
                                                      "plastics": 0.08},
                         labor=0.42, capital=3.2, skill=0.85, dirty=0.15, land=0.1, tech="bioimaging"),
    "aeroworks":    dict(out="aircraft", per=1.0, inp={"alloys": 0.40, "electronics": 0.18,
                                                       "machinery": 0.12, "power": 0.14},
                         labor=0.60, capital=4.4, skill=0.78, dirty=0.30, land=0.2, tech="composite_airframe"),
    "shipyards":    dict(out="ships", per=1.0, inp={"steel": 0.60, "machinery": 0.14,
                                                    "electronics": 0.08, "power": 0.12},
                         labor=0.70, capital=3.4, skill=0.55, dirty=0.50, land=0.4, tech=None),
    "armsworks":    dict(out="arms", per=1.0, inp={"alloys": 0.25, "electronics": 0.15,
                                                   "machinery": 0.10, "chemicals": 0.08},
                         labor=0.50, capital=3.0, skill=0.68, dirty=0.45, land=0.2, tech=None),
    "ordnance":     dict(out="munitions", per=1.0, inp={"chemicals": 0.35, "steel": 0.20, "power": 0.10},
                         labor=0.42, capital=1.8, skill=0.40, dirty=0.70, land=0.2, tech=None),
    "roboworks":    dict(out="robotics", per=1.0, inp={"electronics": 0.25, "alloys": 0.15,
                                                       "software": 0.08, "machinery": 0.06},
                         labor=0.35, capital=3.8, skill=0.82, dirty=0.20, land=0.1, tech="actuator_dense"),
    "spaceworks":   dict(out="satellites", per=1.0, inp={"alloys": 0.30, "electronics": 0.25,
                                                         "semis": 0.05, "fuel": 0.20},
                         labor=0.55, capital=5.5, skill=0.90, dirty=0.30, land=0.2, tech="orbital_lift"),
    "atelier":      dict(out="luxury", per=1.0, inp={"gems": 0.05, "gold": 0.02, "textiles": 0.20},
                         labor=1.4, capital=0.8, skill=0.55, dirty=0.05, land=0.0, tech=None),
    "distillery":   dict(out="spirits", per=1.0, inp={"grain": 0.55, "glass": 0.08, "power": 0.05},
                         labor=0.4, capital=0.9, skill=0.30, dirty=0.25, land=0.1, tech=None),
    "plantations":  dict(out="coffee", per=1.0, inp={"fertilizer": 0.08},
                         labor=1.6, capital=0.4, skill=0.12, dirty=0.25, land=1.4, tech=None),
    "studios":      dict(out="media", per=1.0, inp={"compute": 0.04, "power": 0.02},
                         labor=0.95, capital=0.7, skill=0.60, dirty=0.02, land=0.0, tech=None),
    "banks":        dict(out="finance", per=1.0, inp={"software": 0.05, "compute": 0.03},
                         labor=0.55, capital=1.2, skill=0.75, dirty=0.01, land=0.0, tech=None),
    "shipping":     dict(out="logistics", per=1.0, inp={"fuel": 0.30, "ships": 0.002, "vehicles": 0.004},
                         labor=0.45, capital=2.0, skill=0.30, dirty=0.75, land=0.1, tech=None),
    "smuggling":    dict(out="contraband", per=1.0, inp={"chemicals": 0.10, "logistics": 0.06},
                         labor=0.60, capital=0.6, skill=0.35, dirty=0.30, land=0.1, tech=None, illegal=True),
}

INDUSTRY_LIST = list(INDUSTRIES)

# Which industries a region can host given its resource endowment.
RESOURCE_GATES = {
    "mining_iron": "iron", "mining_cu": "copper", "mining_bx": "bauxite",
    "mining_li": "lithium", "mining_re": "rare_earth", "mining_au": "gold",
    "gemworks": "gems", "uranium_mine": "uranium", "oil_extract": "oil",
    "gas_extract": "gas", "coal_mine": "coal", "forestry": "timber",
    "fishing": "fishery", "farming": "arable", "orchards": "arable",
    "ranching": "pasture", "plantations": "tropical",
}

RESOURCE_KINDS = ["iron", "copper", "bauxite", "lithium", "rare_earth", "gold", "gems",
                  "uranium", "oil", "gas", "coal", "timber", "fishery", "arable",
                  "pasture", "tropical", "hydro", "geothermal", "solar", "wind"]

# ---------------------------------------------------------------------------
# Biomes: (arable, pasture, timber, fishery, habitability, mining_bonus)
# ---------------------------------------------------------------------------
BIOMES = {
    "ice":        dict(arable=0.00, pasture=0.02, timber=0.00, hab=0.03, mine=0.7, symbol="*", col="W"),
    "tundra":     dict(arable=0.05, pasture=0.20, timber=0.05, hab=0.15, mine=1.0, symbol=",", col="Cy"),
    "taiga":      dict(arable=0.15, pasture=0.25, timber=1.00, hab=0.35, mine=1.1, symbol="↑", col="g"),
    "temperate":  dict(arable=0.90, pasture=0.70, timber=0.60, hab=1.00, mine=1.0, symbol="\"", col="G"),
    "grassland":  dict(arable=0.80, pasture=1.00, timber=0.10, hab=0.85, mine=1.0, symbol="_", col="Y"),
    "desert":     dict(arable=0.05, pasture=0.10, timber=0.00, hab=0.20, mine=1.3, symbol="~", col="y"),
    "steppe":     dict(arable=0.35, pasture=0.85, timber=0.05, hab=0.55, mine=1.1, symbol="-", col="y"),
    "savanna":    dict(arable=0.45, pasture=0.90, timber=0.20, hab=0.70, mine=1.1, symbol=";", col="Y"),
    "rainforest": dict(arable=0.30, pasture=0.20, timber=1.20, hab=0.50, mine=1.2, symbol="§", col="g"),
    "mountain":   dict(arable=0.10, pasture=0.30, timber=0.35, hab=0.30, mine=1.8, symbol="▲", col="K"),
    "wetland":    dict(arable=0.40, pasture=0.30, timber=0.40, hab=0.45, mine=0.8, symbol="≈", col="c"),
    "mediterran": dict(arable=0.70, pasture=0.55, timber=0.30, hab=0.95, mine=1.0, symbol="'", col="G"),
    "ocean":      dict(arable=0.00, pasture=0.00, timber=0.00, hab=0.00, mine=0.3, symbol="·", col="bl"),
    "shelf":      dict(arable=0.00, pasture=0.00, timber=0.00, hab=0.00, mine=0.6, symbol=":", col="c"),
}

# Household consumption basket, in units per person per day, by wealth band
# (poor, middle, rich).  These are the anchor of the whole economy: everything
# else — investment, government, procurement — is sized as a share of the value
# of this basket, so the national accounts cannot drift apart.
BASKET = {
    "foodstuffs": (0.00090, 0.0030, 0.0044),
    "produce":    (0.00024, 0.0014, 0.0026),
    "power":      (0.00072, 0.0060, 0.0190),
    "fuel":       (0.00036, 0.0032, 0.0098),
    "textiles":   (0.00016, 0.0011, 0.0030),
    "electronics":(0.000016, 0.00022, 0.00090),
    "vehicles":   (0.0000016, 0.000030, 0.000135),
    "pharma":     (0.000012, 0.00015, 0.00062),
    "medtech":    (0.0000010, 0.000016, 0.000078),
    "media":      (0.000080, 0.00090, 0.00390),
    "finance":    (0.000040, 0.00070, 0.00480),
    "logistics":  (0.000160, 0.00120, 0.00400),
    "luxury":     (0.0000002, 0.0000090, 0.000105),
    "spirits":    (0.000016, 0.00013, 0.00040),
    "coffee":     (0.000024, 0.00022, 0.00068),
    "software":   (0.0000080, 0.00014, 0.00072),
    "cement":     (0.000200, 0.00130, 0.00280),
    "steel":      (0.000120, 0.00090, 0.00200),
}

# Investment demand, as *value shares* of total investment spending.
INVEST_SHARE = {
    "cement": 0.115, "steel": 0.150, "machinery": 0.140, "vehicles": 0.075,
    "electronics": 0.070, "glass": 0.030, "plastics": 0.035, "timber": 0.045,
    "alloys": 0.045, "logistics": 0.050, "software": 0.055, "compute": 0.030,
    "semis": 0.020, "medtech": 0.020, "robotics": 0.020, "aircraft": 0.020,
    "ships": 0.018, "satellites": 0.007, "fertilizer": 0.030, "chemicals": 0.025,
}

# Government (non-military) consumption, as value shares.
GOV_SHARE = {
    "pharma": 0.150, "medtech": 0.075, "foodstuffs": 0.075, "media": 0.060,
    "software": 0.090, "compute": 0.055, "power": 0.090, "fuel": 0.070,
    "logistics": 0.075, "cement": 0.075, "vehicles": 0.055, "electronics": 0.055,
    "finance": 0.035, "textiles": 0.040,
}

# Military procurement, as value shares of the defence budget.
PROCURE_SHARE = {
    "arms": 0.260, "munitions": 0.175, "aircraft": 0.130, "ships": 0.095,
    "vehicles": 0.085, "fuel": 0.130, "electronics": 0.070, "satellites": 0.025,
    "foodstuffs": 0.030,
}

# Research demand, as value shares of the R&D budget.
RESEARCH_SHARE = {
    "compute": 0.30, "software": 0.26, "semis": 0.10, "chemicals": 0.10,
    "medtech": 0.10, "electronics": 0.09, "machinery": 0.05,
}

for _tbl in (INVEST_SHARE, GOV_SHARE, PROCURE_SHARE, RESEARCH_SHARE):
    _t = sum(_tbl.values())
    for _k in _tbl:
        _tbl[_k] /= _t
