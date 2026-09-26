# Indian Valley 🌾

A Stardew Valley-inspired farming and life simulation game set in **Viralpadi Valley**, a lush terraced valley in the foothills of the Western Ghats, rural India.

> *Restore your grandparent's neglected farm, revive the Panchayat Hall, and build meaningful connections with the people of Viralpadi.*

---

## About the Game

Indian Valley is a cozy, handcrafted farming sim where players inherit an overgrown plot of laterite-soil farmland and slowly bring a quiet valley back to life. Grow paddy, spices, and pulses across four Indian seasons (Kharif, Rabi, Winter, Ugadi). Fish the backwaters, forage the Ghats Trail, mine Kanagiri Mines, and befriend — or marry — the 12 unique villagers of Viralpadi.

**Core pillars:**
- Restoration over conquest
- Community as the heart
- Seasonal rhythm (28-day seasons)
- Player expression
- Accessible depth

## Technical Stack

| Layer | Choice |
|---|---|
| Engine | Godot 4 (GDScript) |
| Art | Aseprite — 16×16 tiles, 32×48px sprites |
| Audio | FMOD + Godot AudioStreamPlayer |
| Dialogue | Dialogic 2 (Godot plugin) |
| Save system | JSON (3 slots) |
| Version control | Git + GitHub |
| Target platform | PC (Steam) primary |

## Project Structure

```
Indian-Valley/
├── scenes/           # Godot scene files (.tscn)
│   ├── World/        # Farm, Town, Mines, etc.
│   ├── Player/       # Player character
│   ├── UI/           # HUD, menus, inventory
│   └── Systems/      # Farming tiles, crops, NPCs
├── scripts/          # GDScript source files
│   ├── autoloads/    # Singletons (GameClock, GameData, SaveManager, ItemDB,
│   │                 #   Calendar, Relationships, Weather)
│   ├── player/       # Player controller, tools
│   ├── world/        # Farm, tilemap, environment
│   ├── ui/           # HUD, inventory, dialogue
│   └── systems/      # Farming, economy, relationships
├── assets/           # Sprites, tilesets, audio, fonts
│   ├── sprites/
│   ├── tilesets/
│   └── audio/
├── data/             # JSON data files (items, crops, npcs, festivals, bundles)
└── tests/            # Headless smoke test (SmokeTest.tscn)
```

## Getting Started

1. Install [Godot 4.2+](https://godotengine.org/)
2. Clone this repo: `git clone https://github.com/anandarajRepo/Indian-Valley.git`
3. Open Godot → Import → select the project folder
4. Press F5 to run

## Development Roadmap

| Phase | Goal | Status |
|---|---|---|
| 0 — Foundations | Core loop proof of concept | ✅ Complete |
| 1 — Vertical Slice | Playable Spring season | ✅ Complete |
| 2 — Alpha | Full year one | ✅ Complete |
| 3 — Beta | Content-complete, itch.io demo | ⏳ Planned |
| 4 — Polish | Release-ready | ⏳ Planned |
| 5 — Launch | Steam Early Access | ⏳ Planned |

## Phase 1 — Vertical Slice (Playable Spring)

The game now boots to a **title screen** and plays a full **Spring (Ugadi)**
season loop end to end. Ugadi is the New Year in Viralpadi, so the calendar
begins there and rolls Ugadi → Kharif → Rabi → Winter → Ugadi.

**What's in the slice**

- **Title screen** — New Game / Continue / Quit. Continue loads slot 0.
- **Two connected worlds** — walk the road between your **Farm** and
  **Viralpadi town** (seamless scene warps; the farm keeps its state).
- **Full farming loop** — till → plant → water → grow (overnight) → harvest →
  ship. Crops render through placeholder growth stages; watering must be redone
  each morning; seeds are consumed on planting.
- **9 Spring crops** — okra, amaranth greens, brinjal, ridge gourd, cluster
  beans, watermelon, sunflower, jasmine and marigold.
- **Town life** — talk to villagers (Kavitha, Murugan) via a dialogue box, and
  buy season-appropriate seeds & food at **Kavitha's General Store**.
- **Persistence** — inventory survives Farm↔Town trips; the game auto-saves
  each morning, plus a manual **Save** in the pause menu.
- **UI** — persistent HUD (clock/date, energy, gold, hotbar), a full inventory
  screen, a day-summary card after sleeping, and a pause menu.

**Controls**

| Action | Key(s) |
|---|---|
| Move | WASD / Arrows |
| Use tool / plant | Left-click or X |
| Interact (NPCs, chest, bed) | Z / Enter |
| Hotbar select | 1–5, or Q / E |
| Inventory screen | I / T |
| Sleep (or use the bed) | F |
| Advance dialogue | Z / Enter / X |
| Pause menu | Esc |

Sleep on the farm (bed or **F**), or when energy runs out, to sell the shipping
chest's contents overnight, grow your crops, and start the next day.

## Phase 2 — Alpha (Full Year One)

A complete first year is now playable: all four seasons, weather, festivals,
villager friendships, foraging, fishing and the Panchayat Hall restoration.

**Seasons & farming**

- **23 crops across the whole year** — new Rabi (chickpea, mustard) and Winter
  (methi, radish, hill carrot, garlic) crops join the Ugadi and Kharif rosters.
  Kavitha's store stocks whatever is in season.
- **Season change** — on the first morning of a new season, planted crops that
  can't grow in it **wither**. Clear them with the hoe or sickle.
- **Year rollover** — Winter 28 → Ugadi 1 starts Year 2 with a
  "story so far" review (earnings, harvests, fish, forage, festivals, friends,
  Hall progress).

**Weather** — each day is Sunny, Cloudy, Rain or a Monsoon storm, rolled from
per-season odds (Kharif is the monsoon). Rain waters every tilled tile for you.
The HUD shows today's weather; the journal and day summary show tomorrow's
forecast. Evenings darken and rainy days get falling rain on screen.

**Festivals** — one per season in the town square: **Ugadi Mela** (Ugadi 14),
**Aadi Perukku** (Kharif 16), **Deepavali** (Rabi 20) and **Pongal**
(Winter 14). Hold a crop, forage find or fish and bring it to the offering
stall for gold, a festival treat and friendship with the whole village.

**Villagers & friendship** — six villagers with seasonal, weather, festival
and heart-level dialogue: Kavitha (store), Murugan (farmer), Devi (herbalist),
Ravi (fisherman), Anjali (teacher) and Meenakshi Paati (elder). Chat once a
day and give one gift a day — each villager loves, likes and dislikes
different things, and birthday gifts count ×8. Up to 10 hearts each.

**Ghats Trail** — a new area west of the farm. Seasonal forageables (neem
flowers, raw mango, wild mushrooms, amla, wild honey, ber…) respawn every
morning.

**Fishing** — Ravi gives you a rod when you first meet. Face the farm pond or
the Ghats river and use it: wait for the bite, then reel in when the marker
sweeps through the green zone. 8 fish, varying by season, location and
weather — including the legendary Golden Mahseer.

**Eating** — select food or edible forage in the hotbar and use it to restore
energy.

**Panchayat Hall** — six offering baskets (seasonal crops, forage, fish) in
the town hall. Each completed basket gives a reward; fill them all to restore
the Hall and bring back the Vanam Thay.

**Journal (J)** — a calendar of festivals and birthdays with the forecast,
villager hearts and gift status, and skills plus lifetime stats.

**Saves** — save format v2 adds weather, friendships, festivals, forage, the
Hall and stats. Phase 1 (v1) saves load with sensible defaults.

**New controls**

| Action | Key(s) |
|---|---|
| Journal (calendar / villagers / skills) | J |
| Switch journal tab | Q / E |
| Eat food, cast fishing rod | Left-click or X (with the item selected) |
| Reel in a fish | Z / X / Enter |

### Running the smoke test

```
godot --headless res://tests/SmokeTest.tscn
```

It plays through a new game, rain and growth, a season change, fishing,
foraging, villagers, a festival, the Hall, save/load, v1-save migration and the
year rollover, and exits non-zero on any failure. It uses save slot 2 and
restores whatever was there.

## Setting & Lore

The valley sits near ancient tank irrigation systems built by a forgotten king. Local belief holds that the **Vanam Thay** (Mother of the Forest) once kept the land fertile — but left when the Panchayat Hall fell into disuse. Restoring it is one path back to balance.

## License

All rights reserved — © 2026 Indian Valley Project.
