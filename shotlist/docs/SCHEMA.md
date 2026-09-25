# SHOT LIST data schema and import/export boundaries

Everything SHOT LIST stores is JSON-compatible: string-keyed objects, dense
arrays, strings, numbers and booleans, with no nulls. That makes the on-device
database, the journal and the interchange files readable by any language.

Times are **Playdate epoch seconds** (seconds since 2000-01-01 00:00 UTC; add
946684800 for Unix time). Exports also carry human-readable local
`YYYY-MM-DD` / `HH:MM` strings.

## 1. Files in the game's Data folder

On device the folder is `Data/com.shotlist.playdate/` (Data Disk mode over
USB); in the Simulator it is the Simulator's Data folder.

| Path | Written by | Purpose |
|---|---|---|
| `shotlist.json` | `playdate.datastore` | current snapshot (the whole database) |
| `shotlist_new.json` | snapshot writer | next snapshot; promoted by rename |
| `shotlist_prev.json` | snapshot writer | the previous snapshot |
| `journal.jsonl` | every commit | one op per line since the last snapshot |
| `session.json` | idle writer | UI cursor (not production data) |
| `backups/snapN.json`, `backups/index.json` | backup ring | 8 rolling full snapshots plus metadata |
| `rescue-<t>/` | loader | unreadable snapshots are moved here, never deleted |
| `export/<SLUG>-<YYYYMMDD-HHMM>.json` | EXPORT / WRAP | `shotlist.project` v1 |
| `export/...-shots.csv`, `...-takes.csv` | EXPORT / WRAP | flat tables |
| `export/...-report.txt` | WRAP | rendered wrap report |
| `import/*.json` | **you / companion tool** | read by DATA > IMPORT |

## 2. Database (`shotlist.json`)

```jsonc
{
  "app": "shotlist", "schema": 1,       // schema version; see §6
  "seq": 812,                           // last journal op included
  "nextId": 431, "savedAt": 843000000,
  "settings": { "id": "settings", "k": "settings", "project": "p1", "cursor": "s57",
                "nextMode": "BALANCED", "autoNext": true, "holdMs": 450, "crank": 2, ... },
  "gear": { "id": "gear", "k": "gear",
            "packages": [ { "id": "g2", "k": "pkg", "name": "A CAM", "camera": "SONY FX6",
                            "lenses": ["24-70"], "filters": ["VND"], "support": "", "audio": "", "lighting": "" } ],
            "lists": { "cameras": [], "lenses": [], "filters": [], "support": [], "audio": [], "lighting": [] } },
  "projects": [ PROJECT, ... ]
}
```

Every record has a stable `id` (a kind prefix plus a number, e.g. `s57`) and
`k` (its kind). Child arrays hold the hierarchy:

| kind (`k`) | fields | children |
|---|---|---|
| `project` | `title client director dp producer notes template` · `cast[] locations[]` | `days[]`, `reports[]` |
| `day` | `label date("YYYY-MM-DD") location call("HH:MM") crewNotes weather` · `started` (epoch, first take) | `scenes[]` |
| `scene` | `number desc location cast status` (status is derived from its shots) | `setups[]`, `notes[]` |
| `setup` | `letter camera lens fps res wb iso shutter nd support lighting audio` | `shots[]` |
| `shot` | `num desc size move lens subject priority(1-3) est(min) status notes` · `startedAt doneAt` | `takes[]` |
| `take` | `n t rating circle tech perf note` | |
| `note` (continuity) | `tag text flag resolved shot(id) take(n) t` | |
| `report` | `t day title data{...} lines[]` | |

A shot's code is `scene.number + setup.letter + "-" + shot.num`, e.g. `04B-03`.
It is computed, not stored, so renumbering a scene renames its shots.
`shot.lens` empty means "use the setup lens". Shutter values without `/` are
angles in degrees.

### Controlled vocabularies (`source/core/vocab.lua`)

| field | values |
|---|---|
| status | `NOT SHOT` `UP NEXT` `SHOOTING` `GOT IT` `PICKUP` `CUT` |
| size | `ECU CU MCU MS MWS WS EWS INSERT OTS POV 2-SHOT` |
| move | `LOCKED PAN TILT DOLLY PUSH PULL TRACK HANDHELD GIMBAL CRANE DRONE` |
| lens | `14 18 21 24 28 32 35 40 50 65 75 85 100 135` + any custom string |
| rating | `GREAT GOOD BAD TECH` or `""` (unrated) |
| tag | `WARDROBE PROP HAIR POSITION EYELINE LIGHT CAMERA AUDIO` |
| priority | `1` = A must, `2` = B should, `3` = C nice |

Pickers always offer "TYPE CUSTOM…" for camera fields, so custom strings are
legal in every text field. Readers must accept values outside the lists.

## 3. Journal ops (`journal.jsonl`)

Every mutation goes through `Model.apply(op)`, which is deterministic. The
journal can therefore be replayed, and `apply` returns the inverse op used by
undo.

```jsonc
{"o":"add","p":"u12","c":"shots","r":{...record with id...},"i":3,"s":801,"label":"ADD SHOT"}
{"o":"set","id":"t77","f":"rating","v":"GREAT","s":802}
{"o":"del","id":"s40","s":803}
{"o":"mv","id":"c5","p":"d2","c":"scenes","i":1,"s":804}
{"o":"batch","ops":[...],"s":805,"label":"TAKE 4 04B-03"}
```

`s` is a sequence number that increases monotonically. On load, ops with
`s > db.seq` are replayed. A torn (undecodable) line ends in a crash and is
ignored. A companion tool can tail the journal to follow a shoot live over
USB without parsing the snapshot.

## 4. Export formats

### 4.1 `shotlist.project` v1 (lossless)

```jsonc
{
  "format": "shotlist.project", "version": 1, "schema": 1,
  "exportedAt": "2026-09-25T19:19", "exportedAtEpoch2000": 843160740,
  "project": { ...PROJECT without "k", every shot also has "code": "04B-03"... },
  "gear": { "packages": [...], "lists": {...} }
}
```

A machine-readable JSON Schema is in
[`schema/shotlist-project.schema.json`](schema/shotlist-project.schema.json).

### 4.2 `...-shots.csv` (one row per shot; RFC 4180, CRLF)

`day,date,scene,sceneDesc,location,cast,setup,camera,setupLens,fps,res,wb,iso,shutter,nd,support,lighting,audio,shot,code,desc,size,move,lens,subject,priority,est,status,notes,takes,best,circled`

`priority` is `A/B/C`, `best` is the best take number, and `circled` holds
the circled take numbers separated by spaces.

### 4.3 `...-takes.csv`

`code,take,time,rating,circle,tech,perf,note`

## 5. Import boundary: what a companion tool must produce

The device imports only **JSON files in `import/`**, and only two document
types. All CSV, StudioBinder and ShotDeck parsing belongs in the companion
tool, which reduces those sources to one of these:

### 5.1 `shotlist.shots` v1: flat rows (the recommended converter target)

```json
{
  "format": "shotlist.shots", "version": 1,
  "project": { "title": "ACME PROMO", "client": "ACME", "director": "", "dp": "", "producer": "",
               "notes": "", "cast": ["SAM"], "locations": ["STUDIO"] },
  "shots": [
    { "day": "DAY 1", "date": "2026-10-01", "scene": "1", "sceneDesc": "OPEN", "location": "STUDIO",
      "setup": "A", "camera": "A CAM", "setupLens": "35", "fps": "23.976",
      "shot": "1", "desc": "HERO WIDE", "size": "Wide", "move": "Static", "lens": "35mm",
      "subject": "SAM", "priority": "A", "est": 15, "status": "", "notes": "" }
  ]
}
```

- Rows are grouped into days, then scenes (by `scene` within a day), then
  setups (by `setup` letter within a scene), in the order they first appear.
  Only `desc` or `size` is needed for a useful shot. Every other column is
  optional.
- A missing `shot` number is auto-numbered `01, 02…` within its setup. A
  missing `setup` defaults to `A`, and a missing `day` to `DAY 1`.
- Setup-level columns (`camera fps res wb iso shutter nd support lighting
  audio setupLens`) are read from the **first** row of each setup.
- Values are normalised to the vocabularies, including common aliases:
  `Close Up→CU`, `Wide→WS`, `Two Shot→2-SHOT`, `Static/Locked off→LOCKED`,
  `Steadicam→GIMBAL`, `Push In→PUSH`, `done/complete→GOT IT`,
  `omit→CUT`, `pick up→PICKUP`. A trailing `mm` is stripped from lenses.
  Priority accepts `A/B/C`, `1/2/3`, `High/Med/Low` and `Must/Nice`.
  Values that don't match are kept, uppercased, and reported as warnings.
- The file is capped at 2000 rows.

### 5.2 `shotlist.project` v1: nested

This is our own export (§4.1), usable for round trips, backup transfer or a
tool that builds the tree itself. Takes, circles, notes and timestamps are
imported. Ids are always reassigned. `version` greater than the device's
version is refused.

### 5.3 Suggested source mappings (for the companion tool)

| Source | Maps to |
|---|---|
| Our `-shots.csv` | rows of §5.1 as-is (same column names) |
| StudioBinder shot list CSV | `Scene`→scene, `Shot`→shot, `Shot Size`→size, `Camera Movement`→move, `Lens`→lens, `Description`→desc, `Subject`/`Cast`→subject, `Camera`→camera, `Est. Time`→est (min), `Notes`→notes |
| ShotDeck-style reference lists | `Shot Type`/`Framing`→size, `Camera Movement`→move, `Lens Size`→lens, `Title`/`Description`→desc; references become `notes` |
| Generic spreadsheet | anything with scene/setup/desc/size columns |

No networking is implemented or faked. The exchange medium is files in the
Data folder.

## 6. Versioning and migration

- `db.schema` is the database version (currently **1**). `Schema.MIGRATIONS[v]`
  upgrades v→v+1 in place and runs on load. Shipped migrations are never
  edited; a new one is appended and `Schema.VERSION` bumped.
- A database with `schema` greater than the app's version is **refused**
  (the loader falls back to older snapshots or backups). It is never
  truncated.
- Missing fields are filled from `Schema.DEFAULTS` when a record is loaded,
  and unknown fields are preserved. Newer companion tools can add fields
  without breaking older devices.
- Interchange documents carry their own `format` and `version`, independent
  of the database schema.
