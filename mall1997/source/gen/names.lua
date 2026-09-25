-- Name and word tables for procedural content. All brands are fictional.

Names = {}

Names.teenFirst = {
  "Jessica", "Ashley", "Amanda", "Brittany", "Sarah", "Stephanie", "Jennifer", "Heather", "Nicole",
  "Megan", "Crystal", "Tiffany", "Kelly", "Amber", "Danielle", "Lindsay", "Erin", "Courtney",
  "Kristen", "Rachel", "Tara", "Mandy", "Jenna", "Shawna", "Tasha", "Keisha", "Monique", "Vanessa",
  "Alicia", "Marisol", "Leah", "Kim", "Joy", "Becca", "April", "Dawn",
  "Michael", "Christopher", "Matthew", "Joshua", "Justin", "Brandon", "Ryan", "Tyler", "Kyle",
  "Andrew", "Jason", "Travis", "Derek", "Corey", "Jeremy", "Dustin", "Chad", "Brian", "Eric",
  "Kevin", "Jamal", "Marcus", "Andre", "Luis", "Carlos", "Danny", "Trevor", "Cody", "Shane",
  "Nate", "Seth", "Adam", "Zack", "Josh", "Tim", "Wes", "Rob", "Omar", "Devon", "Kenny",
}
Names.adultFirst = {
  "Linda", "Debbie", "Karen", "Susan", "Donna", "Cheryl", "Pam", "Brenda", "Tammy", "Lori",
  "Denise", "Patty", "Sandra", "Diane", "Gail", "Rhonda", "Terri", "Janet", "Carol", "Wendy",
  "Gloria", "Yolanda", "Maria", "Rosa", "Joan", "Marge", "Bev", "Lynn", "Connie", "Nadine",
  "Gary", "Steve", "Mike", "Dave", "Rick", "Doug", "Randy", "Jeff", "Mark", "Tom", "Ron",
  "Bill", "Jim", "Larry", "Dennis", "Keith", "Greg", "Al", "Phil", "Walt", "Frank", "Ray",
  "Ed", "Stan", "Glenn", "Carl", "Hector", "Raymond", "Curtis", "Leon", "Victor", "Ned", "Hal",
}
Names.oldFirst = {
  "Edna", "Mildred", "Dorothy", "Irene", "Marjorie", "Harriet", "Lois", "Vera", "Ruth", "Hazel",
  "Walter", "Harold", "Earl", "Herb", "Norman", "Ralph", "Bernard", "Chester", "Floyd", "Milton",
}
Names.last = {
  "Anderson", "Baker", "Castillo", "Dunn", "Ellis", "Fischer", "Garza", "Hollis", "Ingram",
  "Jensen", "Kowalski", "Lindqvist", "Morales", "Nguyen", "Okafor", "Petrakis", "Quinn", "Reyes",
  "Schaefer", "Tran", "Underwood", "Vance", "Whitaker", "Yoder", "Zimmerman", "Brandt", "Carver",
  "DeLuca", "Esposito", "Ferris", "Gallagher", "Hart", "Iverson", "Jablonski", "Kim", "Lambert",
  "McAllister", "Novak", "O'Brien", "Park", "Rizzo", "Stroud", "Thibodeaux", "Voss", "Walsh",
  "Abernathy", "Birch", "Coombs", "Dietrich", "Fontaine", "Greer", "Holloway", "Jimenez", "Kessler",
  "Lutz", "Marsh", "Nakamura", "Ortega", "Pruitt", "Radley", "Sokolov", "Tate", "Vogel", "Webb",
  "Crane", "Delgado", "Pham", "Washington", "Jackson", "Robinson", "Coleman", "Haines", "Mercer",
}

Names.neighborhoods = {
  "Oak Hollow", "Briar Ridge", "the Pines apartments", "Cedar Crest", "Willow Park", "the east side",
  "Lakeview Estates", "the trailer park off Route 9", "Maple Glen", "downtown", "Foxrun",
  "the new subdivision", "Hillcrest", "a duplex on Fourth Street", "Sunnyvale Terrace",
}
Names.schools = { "Ridgemont High", "Westfield High", "St. Agnes Academy", "Lincoln High", "Eastbrook High" }

-- --------------------------------------------------------------- stores
Names.storeNames = {
  clothing = { "Threadbare", "Denim Depot", "The Gap Year", "Flannel Republic", "Urban Outpost",
    "Casual Friday", "Stitch & Co.", "Hemline", "Rag Trade", "Mod Squad", "Cotton Candy Club",
    "The Limited Edition", "Baggy's", "Plaid Nation", "Wear House" },
  shoes = { "Sole Mates", "Foot Locale", "Heel Street", "The Shoe Tree", "Kicks Station",
    "Lace Place", "Stride Ahead", "Platform 9" },
  electronics = { "Circuit Village", "Radio Ranch", "Beeper Barn", "Byte Barn",
    "Watts Up", "Sound & Vision", "The Gadget Cove" },
  music = { "Vinyl Countdown", "Sam's Records", "Rhythm Den", "Groove Garage", "The Record Rack",
    "Wax Museum", "Ear Candy Music" },
  video = { "Reel Deal Video", "Rewind Video", "Big Box Video", "Mega Movies", "Tape Worm Video" },
  books = { "Paperback Planet", "Chapter & Verse", "The Bookworm", "Dog-Ear Books", "Page Turners" },
  toys = { "Toy Chest", "Kiddie Kastle", "Fun Factory", "Wonder Toys", "The Rocking Horse" },
  games = { "Game Zone", "Cartridge King", "Level Up", "Pixel Palace", "Joystick Junction" },
  jewelry = { "Golden Touch", "Karat Top", "Diamond Lane", "Silver Linings", "Charm City" },
  department = { "Hargrove's", "Bellamy & Stone", "J.T. Pruitt", "Monarch", "Sayer-Kline",
    "Delacorte's", "Wendell & Sons" },
  sporting = { "Varsity Outfitters", "Pro Shop", "Big Game Sports", "Team Spirit", "The Locker" },
  gifts = { "Kooky Kiosk Novelties", "Knick Knack Shack", "Candle Cove", "Wicked Gifts", "Card Carrying" },
  photo = { "One Hour Photo", "Photo Finish", "Shutterbug", "Snapshot Express" },
  salon = { "Hair Affair", "Shear Madness", "Curl Up & Dye", "Mane Street", "The Clip Joint" },
  food = { "Pizza Pronto", "Corn Dog Corral", "Teriyaki Express", "Taco Rodeo",
    "Twisted Pretzel Co.", "Citrus Whip", "Swirl Buns", "Cookie Jar Co.", "Burger Barn", "Jade Wok",
    "Frank's Franks", "Gyro Hero", "Yogurt Mountain", "Hero Hut" },
  restaurant = { "Ruby's Diner", "The Olive Grove", "Chili Pepper Grill", "Captain Pete's" },
  arcade = { "Dragon's Keep", "Quarter Quest", "Fun Galaxy", "Laser Lanes Arcade", "Quarters" },
  cinema = { "Cineplex 6", "Starlite Cinemas", "Galaxy 6" },
  services = { "Key Kiosk", "Mr. Fix-It Shoe & Key", "Tax Pros", "Optical Outlet", "Mall Pharmacy",
    "Four Eyes Optical", "Cut-Rate Tailor" },
  weird = { "The Crystal Cavern", "Mr. Bob's Batteries & Lizards", "Spoon Emporium",
    "Sock Planet", "Nothing Over $1", "The Magnet Man", "Tarot & Taffy", "Gravity Hats",
    "Wallpaper Wizard", "Lamp Land", "Clocks Clocks Clocks", "Beanbag Nation" },
}

Names.companies = {
  "Tristate Retail Group", "Hollis Holdings", "family-owned", "Consolidated Brands Inc.",
  "Mid-America Merchants", "a franchisee from Dayton", "Brightline Corp.", "Pruitt Family Trust",
  "an out-of-state conglomerate", "a couple from church", "Sunbelt Ventures", "Omni Retail",
}

-- --------------------------------------------------------------- music
Names.genres = { "grunge", "alt-rock", "ska-punk", "hip-hop", "r&b", "pop", "electronica",
  "country", "metal", "swing", "trip-hop", "emo", "riot grrrl", "indie", "boy band", "jam band" }
Names.scenes = { "college radio", "MTV", "local scene", "Top 40", "underground", "import only" }

Names.bandA = { "Velvet", "Static", "Neon", "Paper", "Glass", "Silver", "Broken", "Sugar", "Cherry",
  "Plastic", "Lunar", "Velcro", "Cactus", "Tragic", "Electric", "Suburban", "Hollow", "Rocket",
  "Cosmic", "Mercury", "Honey", "Cardboard", "Dial Tone", "Pocket", "Atomic", "Swing Set", "Tiger",
  "Northern", "Slow", "Grape", "Satellite", "Chrome", "Velour" }
Names.bandB = { "Hum", "Machine", "Kids", "Horses", "Martyrs", "Parade", "Theory", "Sons", "Planes",
  "Lanterns", "Collective", "Club", "Weather", "Hearts", "Dolls", "Girls", "Boys", "Arcade",
  "Division", "Summer", "Engines", "Freakout", "Sound System", "Crew", "Monsters", "Lovers",
  "Fever", "Riot", "Garden", "Ghosts", "Brigade" }
Names.bandSolo = { "MC Tectonic", "DJ Lil Pager", "Kandi Kane", "Jewel Tone", "Sharelle", "Big Ron D",
  "Dusty Rhodes Jr.", "Tamika Vale", "Lady Neptune", "K-Nine", "Brent Fairweather", "Nova" }
Names.albumA = { "Songs for", "Life in", "Goodbye", "Welcome to", "The Last", "Tuesday", "Somewhere",
  "Nothing", "Burn", "Low", "Blue", "Parking Lot", "Supernova", "Static", "Radio", "Everything",
  "Fake", "Wonder", "Sleeping", "Minimum Wage", "Food Court", "Escalator", "Pager" }
Names.albumB = { "the Weekend", "Suburbia", "Nowhere", "Forever", "Summer", "Girl", "Heaven", "Rain",
  "Machines", "Vol. 2", "Hotel", "Noise", "Dreams", "Blues", "Lullabies", "Anthems", "Etc.",
  "Motel", "Diary", "Receipts", "Frequencies", "Daydream", "Overdrive" }

-- --------------------------------------------------------------- movies
Names.movieGenres = { "action", "comedy", "horror", "romance", "sci-fi", "drama", "family",
  "thriller", "teen", "indie" }
Names.movieTemplates = {
  action = { "Hard Target {n}", "Maximum {w}", "Code Name: {w}", "{w} Force", "Terminal {w}",
    "Deadline", "Blast Radius", "Sudden Velocity", "Air Marshal", "Final Descent" },
  comedy = { "My Cousin {n}", "Two Guys and a {w}", "Dude, Where's {n}?", "Totally {w}",
    "Mall Cops", "Weekend at {n}'s", "The Substitute Dad", "Big Fat Wedding Crashers" },
  horror = { "Scream Night {k}", "The {w} Beneath", "Don't Answer the Pager",
    "I Know What You Did at the Mall", "Camp Bloodlake {k}", "The Haunting of Room 9" },
  romance = { "Sleepless in {c}", "While You Were {w}", "Love, {n}", "Only You, Tonight",
    "The Wedding Planner's Sister", "Autumn in {c}" },
  ["sci-fi"] = { "Star {w}", "Galactic {w}", "Planet {w}", "The {w} Protocol", "Contact Zero",
    "Cyber Knight", "Men in Beige", "Deep {w} Impact" },
  drama = { "The {w} Redemption", "A River Runs {w}", "Good Will {n}", "The Quiet Year",
    "Rain Over {c}", "The Long Way Home" },
  family = { "Air Bud {k}", "Beethoven's {k}th", "Flubber 2: Flubbier", "Homeward {w}",
    "Talking Dog Christmas", "Jingle All the Mall" },
  thriller = { "The {w} Game", "Conspiracy {w}", "Face/{w}", "Absolute {w}", "The Peacekeeper" },
  teen = { "She's All {w}", "Can't Hardly {w}", "10 Things I {w}", "Varsity {w}", "Clueless in {c}",
    "Senior Skip Day" },
  indie = { "Clerks at Night", "Slacker {w}", "Suburbia Blues", "Kicking and {w}",
    "The Brothers {n}", "Mallrats II: Rattier" },
}
Names.movieWords = { "Impact", "Justice", "Velocity", "Horizon", "Legacy", "Pressure", "Shadow",
  "Fury", "Paradise", "Protocol", "Eclipse", "Vendetta", "Thunder", "Fever", "Wild", "That",
  "Sleeping", "Bound", "Clueless", "Redemption", "Wait", "Hate About You", "Blues", "Freefall" }
Names.cities = { "Seattle", "Tucson", "Cleveland", "Des Moines", "New York", "Boise", "Paris", "Omaha" }
Names.stars = { "Brad Pittman", "Julia Robertson", "Tom Hankerson", "Keanu Rivers", "Sandra Bullard",
  "Will Smithers", "Meg Ryland", "Nicolas Cagely", "Leo DiCapra", "Drew Barrymore-Smith",
  "Jim Carreyson", "Winona Rider", "Bruce Willoughby", "Alicia Silver", "Chris O'Donnelly",
  "Jean-Claude Van Dammit", "Neve Campbeltown", "Matthew Perrywinkle" }
Names.ratings = { "G", "PG", "PG-13", "R" }

-- --------------------------------------------------------------- games
Names.videoGames = { "Crash Bandit 2", "Star Pilot 64", "Super Kart Kids", "Crypt Runner",
  "Final Fantasia VII", "Agent 00-Zero", "Iron Fist Tournament 3", "Metal Gear Hush", "Sparky the Dragon",
  "Resident Weevil", "Banjo & Kazoo", "Diddy Racer", "Pocket Critters Red", "NBA Jam Session '98",
  "Gridiron '98", "Nightcastle: Requiem", "Twisted Metal Mind", "Rhythm Toast" }

-- --------------------------------------------------------------- misc
Names.clothes = {
  { "flannel shirt", 2400 }, { "wide-leg jeans", 3900 }, { "baby tee", 1400 }, { "windbreaker", 4500 },
  { "choker", 800 }, { "platform sneakers", 5500 }, { "skate shoes", 4800 }, { "bucket hat", 1600 },
  { "baseball cap", 1500 }, { "overalls", 3200 }, { "slip dress", 2900 }, { "cargo pants", 3400 },
  { "band tee", 1800 }, { "puffy vest", 4200 }, { "mood ring", 900 }, { "butterfly clips", 500 },
  { "chain wallet", 1200 }, { "velour tracksuit", 5900 }, { "tie-dye shirt", 1300 },
  { "denim jacket", 5200 }, { "turtleneck", 2200 }, { "fleece pullover", 3800 },
}
Names.foodItems = {
  pizza = { { "pizza slice", 225 }, { "pepperoni slice", 275 }, { "garlic knots", 199 } },
  hotdog = { { "corn dog", 199 }, { "cheese on a stick", 249 }, { "fresh lemonade", 225 } },
  asian = { { "teriyaki bowl", 499 }, { "orange chicken", 525 }, { "egg roll", 149 } },
  mexican = { { "bean burrito", 299 }, { "nachos", 249 }, { "taco", 129 } },
  pretzel = { { "cinnamon pretzel", 229 }, { "salted pretzel", 199 }, { "pretzel bites", 249 } },
  drink = { { "citrus whip", 249 }, { "strawberry whip", 269 }, { "large soda", 149 } },
  sweet = { { "swirl bun", 279 }, { "cookie", 99 }, { "frozen yogurt", 239 } },
  burger = { { "cheeseburger", 299 }, { "fries", 149 }, { "shake", 219 } },
}
Names.weirdItems = { { "lava lamp", 2400 }, { "geode", 800 }, { "Magic Eye poster", 1200 },
  { "baby iguana (live)", 3500 }, { "decorative spoon", 600 }, { "D batteries x8", 700 },
  { "glow-in-dark stars", 400 }, { "novelty clock", 1900 }, { "jar of old keys", 300 },
  { "tarot deck", 1500 }, { "beanbag chair", 4900 }, { "fridge magnet", 200 } }
Names.toyItems = { { "Plush Pal (Bongo the Bear)", 600 }, { "Plush Pal (Peace the Bear)", 600 },
  { "Pocket Critter virtual pet", 1700 }, { "yo-yo", 499 }, { "Koosh ball", 399 },
  { "Giggle Me Gus", 2999 }, { "slap bracelet", 199 }, { "Pogs tube", 499 },
  { "Aqua Blaster 3000", 2499 }, { "Talk-Back recorder", 3499 } }
Names.bookItems = { { "Night Shivers #23", 399 }, { "Baby-Sitters Guild #88", 399 },
  { "SAT prep book", 1999 }, { "Chicken Broth for the Teen Soul", 1295 },
  { "Magic Eye III", 1495 }, { "Bridget's Diary", 1195 }, { "The Guitar Chord Bible", 995 },
  { "Sixteen & Up magazine", 299 }, { "Game Power magazine", 499 }, { "Ask Jeeves Almanac", 899 } }
Names.giftItems = { { "scented candle", 999 }, { "friendship necklace", 1499 }, { "glitter pen set", 699 },
  { "funny mug", 899 }, { "Yin-Yang keychain", 499 }, { "incense pack", 399 } }
Names.jewelryItems = { { "silver chain", 3999 }, { "hemp necklace", 899 }, { "class ring deposit", 5000 },
  { "toe ring", 1299 }, { "birthstone earrings", 2499 } }
Names.sportItems = { { "hacky sack", 499 }, { "basketball", 1999 }, { "skateboard deck", 4999 },
  { "satin team jacket", 7999 }, { "rollerblades", 8999 }, { "sweatband set", 499 } }
Names.electronicItems = { { "Discman", 7999 }, { "Walkman", 3999 }, { "AA batteries", 499 },
  { "headphones", 1999 }, { "blank tapes (3pk)", 599 }, { "cordless phone", 4999 },
  { "clear phone", 3999 }, { "pager clip", 699 } }
Names.photoItems = { { "disposable camera", 999 }, { "film roll", 499 }, { "photo album", 1299 } }
Names.serviceItems = { { "key copy", 250 }, { "watch battery", 699 }, { "shoe shine", 500 } }

Names.cliques = { "skaters", "preps", "alt kids", "band kids", "jocks", "mall rats", "goths", "nerds" }
Names.cliqueTaste = {
  skaters = { "ska-punk", "hip-hop", "grunge" }, preps = { "pop", "r&b", "boy band", "country" },
  ["alt kids"] = { "alt-rock", "indie", "riot grrrl", "trip-hop" }, ["band kids"] = { "swing", "jam band", "indie" },
  jocks = { "hip-hop", "metal", "country" }, ["mall rats"] = { "pop", "hip-hop", "ska-punk" },
  goths = { "electronica", "trip-hop", "metal" }, nerds = { "electronica", "emo", "indie", "swing" },
}
