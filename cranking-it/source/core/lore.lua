-- CRANKING IT :: core/lore
-- The Keeper's stories (bought with gears) and the Exhibit Hall catalogue.

Lore = {}

-- Keeper fragments: cost gears; `after` = lifetime gears earned required
Lore.FRAGMENTS = {
  { id = "l1", title = "The Rock", cost = 1, after = 0, text = {
    "The museum stands on a rock the charts call Ninefold. No boat has been scheduled here since the last timetable was printed.",
    "People still come. They climb the stairs out of the water and they are always holding their right hand a little curled, as if around a handle.",
  } },
  { id = "l2", title = "The Society", cost = 1, after = 4, text = {
    "Before the museum there was a Society. The Honourable Company of Hand-Turners. Very dull people. Very punctual.",
    "They held one belief. Nothing moves by itself. Every tide, every season, every heartbeat is being turned by somebody, somewhere.",
  } },
  { id = "l3", title = "The Ledger", cost = 2, after = 10, text = {
    "The Society kept a ledger of every crank in the world and who was turning it.",
    "The last page has one line on it. It says: 'Ninefold. Thirteen machines. Keeper.' And then there is a space where a name should go.",
  } },
  { id = "l4", title = "Stopping", cost = 2, after = 18, text = {
    "When people stop turning, things do not stop at once. They coast. A flywheel remembers its hand for a long time.",
    "That is why the world still seems to work. We are living on momentum. I have measured it. It is running down.",
  } },
  { id = "l5", title = "The Safe", cost = 2, after = 26, text = {
    "There is a safe in the cellar that nobody has opened. The combination was never written down; the Society said a secret should be kept by the hand, not by paper.",
    "Some nights I hear its tumblers falling, very slowly, one by one. Someone is working it from the inside.",
  } },
  { id = "l6", title = "Weather", cost = 2, after = 34, text = {
    "The wind here blows only when the winch is worked. I tested it for a year. Log attached. The Society was not surprised.",
    "They said the sailors had it backwards: you do not trim the sail to the wind. You grind the wind in.",
  } },
  { id = "l7", title = "The Well", cost = 3, after = 44, text = {
    "The well in the courtyard goes further down than the rock does. I dropped a lantern once. It is still falling.",
    "The Society's note on the well reads, in full: 'Do not lower the Keeper.' It is underlined three times.",
  } },
  { id = "l8", title = "Numbers", cost = 3, after = 54, text = {
    "The radio in the east gallery picks up a station that reads numbers. I have decoded them. They are dates.",
    "Most of them are in the past. The rest are the days on which somebody new will come up the stairs.",
  } },
  { id = "l9", title = "Film", cost = 3, after = 64, text = {
    "A photograph is time with the crank taken out. A film is time with the crank put back.",
    "The projectionist who worked here swore that if you cranked the last reel backwards, the audience would stand up and walk out through the doors they came in by. Backwards. Into the sea.",
  } },
  { id = "l10", title = "Clocks", cost = 3, after = 76, text = {
    "Every clock in the museum is correct and every clock shows a different time. This is not a contradiction.",
    "Each one is keeping a different thing. The long-case clock by the stairs keeps the time I have left.",
  } },
  { id = "l11", title = "History", cost = 3, after = 88, text = {
    "I once turned a civilization for eleven thousand years. They built a statue of the hand. Not of me. Of the hand.",
    "When they fell I kept turning out of politeness. Something else grew in the ruins. It built a smaller statue.",
  } },
  { id = "l12", title = "The Last Machine", cost = 4, after = 100, text = {
    "The thirteenth machine turns geological time. The Society built it last and used it once.",
    "They wanted to know if anything waits at the end. The ledger says only: 'Yes. A hand.'",
  } },
  { id = "l13", title = "Succession", cost = 5, after = 120, text = {
    "I was a visitor once. I came up the stairs holding my hand curled around nothing, and the Keeper before me put a crank in it.",
    "You have been very patient with an old machine. The space in the ledger has your handwriting in it now. You did not notice when you wrote it. Nobody ever does.",
  } },
}

function Lore.owned(id) return Save.data.lore[id] == true end

function Lore.available(f) return Save.data.gearsEarned >= f.after end

function Lore.buy(f)
  if Lore.owned(f.id) then return true end
  if not Lore.available(f) then return false end
  if not Save.spendGears(f.cost) then return false end
  Save.data.lore[f.id] = true
  Save.markDirty()
  return true
end

------------------------------------------------------------------------
-- Exhibits: restored with gears once their condition is met
------------------------------------------------------------------------
local function medalOn(id, n)
  return function()
    local r = Save.machine(id)
    for _, v in pairs(r.medals) do if v >= n then return true end end
    return false
  end
end
local function played(id) return function() return Save.machine(id).plays > 0 end end

Lore.EXHIBITS = {
  { id = "e_safe", machine = "safecracker", name = "Harrow Mk.VII Wheel Pack", cost = 2, cond = medalOn("safecracker", 1), need = "A medal on SAFECRACKER",
    text = "Three brass wheels, each with a single gate. The fence drops only when all three line up. Recovered from a bank that no longer has a street." },
  { id = "e_fish", machine = "fishing", name = "The Grey Line", cost = 2, cond = medalOn("fishing", 1), need = "A medal on FISHING LINE",
    text = "Forty fathoms of braided horsehair, snapped at the far end. Whatever took it is listed in the catalogue as 'still pulling'." },
  { id = "e_cam", machine = "camera", name = "Contact Sheet No. 44", cost = 2, cond = medalOn("camera", 1), need = "A medal on FILM CAMERA",
    text = "Twenty-four frames of the same harbour. On frame 17 there is a ship that is not in any of the others, and a man on its deck who is waving." },
  { id = "e_fiche", machine = "microfiche", name = "Reel 1889-B", cost = 2, cond = medalOn("microfiche", 1), need = "A medal on MICROFICHE",
    text = "A year of the Ninefold Gazette on a spool the size of a biscuit. Page 212 has been cranked past so often it is worn transparent." },
  { id = "e_num", machine = "numbers", name = "Receiver, Valve Type", cost = 2, cond = medalOn("numbers", 1), need = "A medal on NUMBERS STATION",
    text = "Tuned permanently to 6.32 MHz. Unplugged since 1961. Still warm." },
  { id = "e_lift", machine = "elevator", name = "Car Switch, Otis Pattern", cost = 2, cond = medalOn("elevator", 1), need = "A medal on ELEVATOR OPERATOR",
    text = "The operator's lever, polished bright where a thumb rested for thirty years. The building it served had eleven floors. The lever has a notch for a twelfth." },
  { id = "e_proj", machine = "projectionist", name = "Changeover Cue Card", cost = 2, cond = medalOn("projectionist", 1), need = "A medal on PROJECTIONIST",
    text = "A card punched with the two dots that tell the projectionist to switch reels. Someone has pencilled a third dot, and underneath: 'never'." },
  { id = "e_light", machine = "lighthouse", name = "First-Order Lens Panel", cost = 2, cond = medalOn("lighthouse", 1), need = "A medal on THE LIGHTHOUSE",
    text = "One of sixteen bull's-eye panels. It floated on a bath of mercury and turned under a keeper's hand for ninety-one years without stopping." },
  { id = "e_winch", machine = "winch", name = "Two-Speed Sheet Winch", cost = 2, cond = medalOn("winch", 1), need = "A medal on SAILBOAT WINCH",
    text = "Bronze, self-tailing, with a handle worn into the shape of two different people's grips. It came off a boat that finished a race nobody else started." },
  { id = "e_well", machine = "well", name = "A Bucket", cost = 3, cond = medalOn("well", 1), need = "A medal on THE WELL",
    text = "Oak staves, iron hoops. Dry. Scratched on the inside bottom, from underneath, in a careful hand: 'thank you for the light'." },
  { id = "e_clock", machine = "clockmaker", name = "Escapement, Grasshopper", cost = 2, cond = medalOn("clockmaker", 1), need = "A medal on CLOCKMAKER",
    text = "A frictionless escapement that needs no oil. It will run for longer than the clock around it. It will run for longer than the room." },
  { id = "e_civ", machine = "civilization", name = "Statue of a Hand", cost = 3, cond = medalOn("civilization", 1), need = "A medal on HAND-CRANKED CIVILIZATION",
    text = "Soapstone, eight centimetres. The fingers are curled around a handle that was carved separately and has been lost." },
  { id = "e_billion", machine = "billion", name = "The Last Sunrise", cost = 4, cond = medalOn("billion", 1), need = "A medal on ONE BILLION YEARS",
    text = "A photograph, apparently taken from the museum steps, of the sun filling half the sky. Exposure: one billion years." },
  { id = "e_keeper", name = "The Keeper's Chair", cost = 5, cond = function() return Save.data.lore.l13 == true end, need = "Hear the Keeper's last story",
    text = "Empty. The cushion is still warm. There is a crank resting on the seat, handle turned toward you." },
}

function Lore.exhibitOwned(e) return Save.data.exhibits[e.id] == true end

function Lore.restore(e)
  if Lore.exhibitOwned(e) then return true end
  if not e.cond() then return false end
  if not Save.spendGears(e.cost) then return false end
  Save.data.exhibits[e.id] = true
  Save.markDirty()
  return true
end
