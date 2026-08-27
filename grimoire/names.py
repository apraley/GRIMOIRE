"""Procedural naming: people, places, states, firms, ships, operations, faiths.

Names are generated from per-culture phoneme tables so the world feels like a
plausible alternate Earth without borrowing real nations or real people.
"""
from __future__ import annotations

from .rng import RNG

CULTURES = [
    "Valdic", "Meritan", "Kesh", "Oranic", "Sundani", "Tsurei",
    "Halric", "Aztlani", "Norvek", "Pashari", "Ombari", "Cirenne",
]

_ONSET = {
    "Valdic":  "b br d dr g gr k kr l m n p pr r s st sv t tr v vl z".split(),
    "Meritan": "b c ch d f g h j k l m n p qu r s sh t th v w".split(),
    "Kesh":    "b d f g h j k kh l m n q r s sh t th w y z".split(),
    "Oranic":  "b br c d f fl g gl l m n p pl r s sc t tr v".split(),
    "Sundani": "b d g h j k l m n ng p r s t w y".split(),
    "Tsurei":  "ch h k m n r s sh t ts y z j".split(),
    "Halric":  "b bl d dh f g h k l m n r s sk t th w".split(),
    "Aztlani": "ch c h ix m n p qu t tl tz x y z".split(),
    "Norvek":  "b d f g h j k kv l m n r s sk st sv t th v".split(),
    "Pashari": "b bh ch d dh g gh j k kh l m n p ph r s sh t v y".split(),
    "Ombari":  "b d f g k kw l m mb n nd ng p s t w y z".split(),
    "Cirenne": "b c ch d f g gh l m n p r s t v z".split(),
}
_VOWEL = {
    "Valdic":  "a e i o u ai ei ou ya".split(),
    "Meritan": "a e i o u ea ee ie oa ou".split(),
    "Kesh":    "a e i o u aa ai ii uu".split(),
    "Oranic":  "a e i o u ia io ua ae".split(),
    "Sundani": "a e i o u ua ai au".split(),
    "Tsurei":  "a e i o u ai ou".split(),
    "Halric":  "a e i o u ae ey oi ui".split(),
    "Aztlani": "a e i o u ua ii oa".split(),
    "Norvek":  "a e i o u au ei oe y".split(),
    "Pashari": "a e i o u aa ii uu ai au".split(),
    "Ombari":  "a e i o u ia oa uu".split(),
    "Cirenne": "a e i o u ai eo ia ie".split(),
}
_CODA = {
    "Valdic":  "d k l m n r s sk st t v z".split() + ["", "", ""],
    "Meritan": "b ck d ft l ld m n nd ng nt r rd s st t".split() + ["", ""],
    "Kesh":    "b d f h l m n q r s sh t z".split() + ["", "", ""],
    "Oranic":  "l m n r s t x".split() + ["", "", "", ""],
    "Sundani": "h k m n ng s t".split() + ["", "", "", ""],
    "Tsurei":  ["n", "", "", "", "", ""],
    "Halric":  "ch d f gh k l m n r sh t th".split() + ["", ""],
    "Aztlani": "c l n tl tz x".split() + ["", "", ""],
    "Norvek":  "d f g k l m n ng r rk s sk st t".split() + ["", ""],
    "Pashari": "d h l m n r s sh t".split() + ["", "", ""],
    "Ombari":  "l m n ng s".split() + ["", "", "", ""],
    "Cirenne": "l n r s t z".split() + ["", "", ""],
}
_SUR_SUFFIX = {
    "Valdic":  ["ov", "ova", "in", "sky", "vic", "enko", "ar", "itz"],
    "Meritan": ["son", "ford", "worth", "ley", "well", "wright", "combe", "field"],
    "Kesh":    ["i", "ani", "zade", "oglu", "vand", "far", "yar"],
    "Oranic":  ["ini", "ossi", "elli", "aro", "ante", "one", "ucci"],
    "Sundani": ["wijaya", "putra", "sari", "nata", "warman", "dinata"],
    "Tsurei":  ["moto", "kawa", "shima", "tani", "hara", "zaki", "no"],
    "Halric":  ["mor", "wyn", "ach", "gan", "lyn", "dor", "rick"],
    "Aztlani": ["atl", "olin", "coatl", "xochi", "teca", "pilli"],
    "Norvek":  ["sen", "strom", "berg", "vik", "dahl", "lund", "gaard"],
    "Pashari": ["ram", "deva", "pal", "raj", "nath", "vardhan", "sena"],
    "Ombari":  ["we", "ke", "ndi", "za", "mba", "oro", "ayo"],
    "Cirenne": ["eau", "ier", "ard", "ette", "on", "aux", "elle"],
}
_PLACE_SUFFIX = {
    "Valdic":  ["grad", "sk", "ovo", "yn", "polje", "bor", "vets"],
    "Meritan": ["ton", "burgh", "port", "shire", "haven", "bridge", "mouth", "chester"],
    "Kesh":    ["abad", "kent", "shahr", "qara", "bagh", "dar"],
    "Oranic":  ["ona", "ento", "ago", "ino", "alta", "amare"],
    "Sundani": ["pura", "karta", "bumi", "laut", "gede"],
    "Tsurei":  ["oka", "shima", "bashi", "hama", "yama", "kyo"],
    "Halric":  ["holm", "gate", "fell", "moor", "keep", "carn"],
    "Aztlani": ["tlan", "pan", "co", "huacan", "mecatl"],
    "Norvek":  ["heim", "fjord", "vik", "stad", "berg", "havn"],
    "Pashari": ["pur", "nagar", "garh", "kot", "sthan", "vati"],
    "Ombari":  ["ville", "zi", "beni", "kuru", "wene"],
    "Cirenne": ["ville", "mont", "val", "lac", "bourg", "rive"],
}

_GIVEN_END_F = {
    "Valdic": ["a", "ia", "ka", "na"], "Meritan": ["a", "ie", "y", "elle"],
    "Kesh": ["a", "eh", "iya"], "Oranic": ["a", "ella", "ina"],
    "Sundani": ["ari", "wati", "ni"], "Tsurei": ["ko", "mi", "ka"],
    "Halric": ["wen", "a", "id"], "Aztlani": ["xochi", "tzin", "a"],
    "Norvek": ["a", "id", "run"], "Pashari": ["a", "i", "ika"],
    "Ombari": ["a", "we", "ni"], "Cirenne": ["e", "ette", "ine"],
}

TITLES = ["Dr.", "Prof.", "Gen.", "Adm.", "Sen.", "Amb.", "Fr.", "Hon.", "Cdr.", "Sir", "Dame"]


def _syll(rng: RNG, culture: str, coda_p: float = 0.45) -> str:
    o = rng.pick(_ONSET[culture])
    v = rng.pick(_VOWEL[culture])
    cd = rng.pick(_CODA[culture]) if rng.chance(coda_p) else ""
    return o + v + cd


def word(rng: RNG, culture: str, syllables: int = 0, coda_p: float = 0.45) -> str:
    n = syllables or rng.weighted([1, 2, 3], [0.2, 0.55, 0.25])
    s = "".join(_syll(rng, culture, coda_p) for _ in range(n))
    s = s.replace("''", "'")
    return s[:1].upper() + s[1:]


def given_name(rng: RNG, culture: str, female: bool | None = None) -> str:
    if female is None:
        female = rng.chance(0.5)
    base = word(rng, culture, rng.weighted([1, 2, 3], [0.25, 0.55, 0.2]), 0.35)
    if female and rng.chance(0.75):
        end = rng.pick(_GIVEN_END_F[culture])
        if base[-1].lower() in "aeiou":
            base = base[:-1]
        base += end
    return base


def surname(rng: RNG, culture: str) -> str:
    base = word(rng, culture, rng.weighted([1, 2], [0.45, 0.55]), 0.4)
    if rng.chance(0.72):
        base += rng.pick(_SUR_SUFFIX[culture])
    return base[:1].upper() + base[1:]


def person_name(rng: RNG, culture: str, female: bool | None = None) -> str:
    return f"{given_name(rng, culture, female)} {surname(rng, culture)}"


def place_name(rng: RNG, culture: str) -> str:
    base = word(rng, culture, rng.weighted([1, 2], [0.5, 0.5]), 0.35)
    if rng.chance(0.65):
        base += rng.pick(_PLACE_SUFFIX[culture])
    else:
        base = f"{base} {rng.pick(['Bay', 'Reach', 'Cross', 'Landing', 'Ford', 'Point', 'Vale', 'Rise'])}"
    return base[:1].upper() + base[1:]


NATION_FORMS = [
    "Republic of {n}", "Federation of {n}", "Kingdom of {n}", "United States of {n}",
    "{n} Union", "Commonwealth of {n}", "People's Republic of {n}", "Emirate of {n}",
    "{n} Confederation", "Empire of {n}", "State of {n}", "Free Cities of {n}",
    "Dominion of {n}", "Sovereign Directorate of {n}", "{n} Compact",
]

CONTINENT_SUFFIX = ["ia", "aria", "ora", "ath", "essa", "una", "irion", "asia", "ander"]

CORP_TAILS = ["Holdings", "Industries", "Group", "Systems", "Dynamics", "Partners",
              "Consolidated", "Works", "Trading Co.", "Logistics", "Capital",
              "Technologies", "Corporation", "Combine", "Ventures", "Foundry",
              "Labs", "Union", "Trust", "Syndicate", "Freight", "Resources"]

CORP_PREFIX = ["Meridian", "Vantage", "Ironvale", "Northlight", "Blackspar", "Solveig",
               "Halcyon", "Argent", "Pallas", "Kestrel", "Obelisk", "Verity",
               "Cardinal", "Sable", "Quarry", "Helion", "Anvil", "Tessellate",
               "Bright Harbor", "Grey Meridian", "Lodestone", "Cinder", "Tallow",
               "Perihelion", "Vector", "Zenith", "Bastion", "Umbral", "Ferrous"]

OP_ADJ = ["SILENT", "IRON", "GLASS", "CRIMSON", "HOLLOW", "PALE", "BROKEN", "LONG",
          "COLD", "BRIGHT", "DEEP", "BLACK", "GOLDEN", "QUIET", "SEVERED", "FALLING",
          "BURNING", "SUNKEN", "WANDERING", "PATIENT", "HUNGRY", "LAST"]
OP_NOUN = ["LANTERN", "COMPASS", "MERIDIAN", "HARVEST", "CATHEDRAL", "ORCHARD",
           "SPINDLE", "ANVIL", "CHORUS", "LEDGER", "ASHES", "TIDE", "KEYSTONE",
           "VESPERS", "MERCURY", "GARDEN", "SIGNAL", "PILGRIM", "CROWN", "SUTURE",
           "MONOLITH", "WOLFRAM", "PRISM", "BELLWEATHER", "TESTAMENT"]

FAITH_ROOT = ["Solar", "Ancestral", "Deep", "Threefold", "Silent", "Eternal", "Woven",
              "Rising", "Hidden", "Open", "Iron", "Green", "First", "Last"]
FAITH_FORM = ["Way", "Covenant", "Communion", "Path", "Order", "Church", "Assembly",
              "Doctrine", "Rite", "Circle", "Testament", "Concord", "Mandate"]

PARTY_ADJ = ["National", "Popular", "Progressive", "Social", "Liberal", "Democratic",
             "Workers'", "Agrarian", "Civic", "Patriotic", "Reform", "Unity",
             "Sovereign", "Green", "Free", "People's", "Constitutional"]
PARTY_NOUN = ["Front", "Party", "Movement", "Alliance", "League", "Bloc", "Congress",
              "Union", "Coalition", "Assembly", "Rally", "Platform"]

PAPER_WORD = ["Sentinel", "Herald", "Ledger", "Chronicle", "Dispatch", "Observer",
              "Register", "Beacon", "Post", "Standard", "Tribune", "Clarion",
              "Record", "Mirror", "Gazette", "Wire", "Digest", "Signal"]

SHIP_ADJ = ["Indomitable", "Resolute", "Vigilant", "Tempest", "Sovereign", "Defiant",
            "Relentless", "Providence", "Ardent", "Intrepid", "Valorous", "Adamant"]

STREET_KIND = ["Row", "Street", "Avenue", "Quay", "Lane", "Terrace", "Boulevard",
               "Passage", "Court", "Wharf", "Arcade", "Embankment"]


def corp_name(rng: RNG, culture: str | None = None) -> str:
    if culture and rng.chance(0.4):
        head = word(rng, culture, 2, 0.4)
    else:
        head = rng.pick(CORP_PREFIX)
    return f"{head} {rng.pick(CORP_TAILS)}"


def operation_name(rng: RNG) -> str:
    return f"{rng.pick(OP_ADJ)} {rng.pick(OP_NOUN)}"


def faith_name(rng: RNG, culture: str) -> str:
    if rng.chance(0.5):
        return f"The {rng.pick(FAITH_ROOT)} {rng.pick(FAITH_FORM)}"
    return f"{word(rng, culture, 2, 0.3)}ism"


def party_name(rng: RNG, culture: str) -> str:
    if rng.chance(0.25):
        return f"{word(rng, culture, 2, 0.35)} {rng.pick(PARTY_NOUN)}"
    return f"{rng.pick(PARTY_ADJ)} {rng.pick(PARTY_NOUN)}"


def outlet_name(rng: RNG, place: str) -> str:
    if rng.chance(0.55):
        return f"The {place} {rng.pick(PAPER_WORD)}"
    return f"{rng.pick(['Continental', 'Global', 'Free', 'Open', 'Public', 'Prime'])} {rng.pick(PAPER_WORD)}"


def nation_name(rng: RNG, culture: str, form: str | None = None) -> tuple[str, str]:
    """Returns (short_name, formal_name)."""
    short = word(rng, culture, rng.weighted([2, 3], [0.6, 0.4]), 0.4)
    if rng.chance(0.55):
        short += rng.pick(["ia", "and", "esh", "ova", "mark", "stan", "ar", "or", "une"])
    short = short[:1].upper() + short[1:]
    formal = (form or rng.pick(NATION_FORMS)).format(n=short)
    return short, formal


def street_address(rng: RNG, culture: str) -> str:
    return f"{rng.randint(1, 480)} {word(rng, culture, 2, 0.3)} {rng.pick(STREET_KIND)}"


def ship_name(rng: RNG, culture: str) -> str:
    return rng.pick(SHIP_ADJ) if rng.chance(0.5) else word(rng, culture, 2, 0.4)


def codename(rng: RNG) -> str:
    return rng.pick(OP_ADJ).title() + " " + rng.pick(OP_NOUN).title()
