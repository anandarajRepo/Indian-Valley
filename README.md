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
│   ├── autoloads/    # Singletons (GameClock, GameData, SaveManager, ItemDB)
│   ├── player/       # Player controller, tools
│   ├── world/        # Farm, tilemap, environment
│   ├── ui/           # HUD, inventory, dialogue
│   └── systems/      # Farming, economy, relationships
├── assets/           # Sprites, tilesets, audio, fonts
│   ├── sprites/
│   ├── tilesets/
│   └── audio/
└── data/             # JSON data files (crops, NPCs, items, recipes)
```

## Getting Started

1. Install [Godot 4.2+](https://godotengine.org/)
2. Clone this repo: `git clone https://github.com/anandarajRepo/Indian-Valley.git`
3. Open Godot → Import → select the project folder
4. Press F5 to run

## Development Roadmap

| Phase | Goal | Status |
|---|---|---|
| 0 — Foundations | Core loop proof of concept | 🚧 In progress |
| 1 — Vertical Slice | Playable Spring season | ⏳ Planned |
| 2 — Alpha | Full year one | ⏳ Planned |
| 3 — Beta | Content-complete, itch.io demo | ⏳ Planned |
| 4 — Polish | Release-ready | ⏳ Planned |
| 5 — Launch | Steam Early Access | ⏳ Planned |

## Setting & Lore

The valley sits near ancient tank irrigation systems built by a forgotten king. Local belief holds that the **Vanam Thay** (Mother of the Forest) once kept the land fertile — but left when the Panchayat Hall fell into disuse. Restoring it is one path back to balance.

## License

All rights reserved — © 2026 Indian Valley Project.
