# Changelog

All notable changes to Indian Valley. Versions follow the development
roadmap in the README.

## 0.9.0-rc1 — Phase 4: Polish (release candidate)

### Added
- **Audio.** Every sound is synthesised in-engine, so no asset files are needed:
  - a looping background tune in raga Mohanam over a tanpura-style drone
  - sound effects for tools, harvests, coins, mining, fishing, gifts, menus,
    level-ups and Hall rewards
  - a rain ambience loop on rainy days, which you don't hear in the mines
  - separate Master, Music and SFX buses
- **Options.** The options menu adds volume sliders for each bus, a text-speed
  setting (slow, normal, fast, instant), a pause-on-focus-loss toggle and a
  "Reset to defaults" button. All options are saved in `user://settings.cfg`.
- **Typewriter dialogue.** Dialogue lines type out with a soft blip. The first
  press shows the whole line and the next press moves on.
- **Fades.** The screen fades in from black whenever the scene changes.
- **Gamepad support.** You can play with a gamepad:
  - move with the left stick or d-pad
  - A to interact, X to use a tool, LB/RB to change the hotbar slot, Y for the
    inventory, Back for the journal, Start or B to pause or close
  - every menu takes focus, so you can drive all of them with a gamepad
- **Level-ups.** Skill level-ups now show a notification and play a fanfare.
- **Low-energy warning.** The energy bar turns red when energy is low.
- **Credits.** The title screen has a Credits page, which includes the Godot
  Engine MIT licence notice.
- **Release builds.** New "Windows (release)" and "Linux (release)" export
  presets, which are not demo builds, and `tools/export_release.sh` to build
  them.

### Changed
- **Saves can survive a crash.** The game writes each save to a temporary file,
  checks it, and keeps the previous save as `.bak`. If a save file is damaged,
  the game loads the backup instead. The slot picker marks a slot it can't
  read as "Damaged save".
- **Closing the window mid-game saves first.**
- **The game pauses when its window loses focus.** You can turn this off in
  Options.
- **The game uses the GL Compatibility renderer.** `project.godot` listed this
  feature but never set it, so desktop builds needed Vulkan.
- **Minimum window size** is now 960×540.
- **The demo never saves Year 2** over the last Year 1 save.

## 0.3.0-beta — Phase 3: Beta
Year One is content-complete and ships as an itch.io demo. This version adds
the Kanagiri Mines, Selvam's forge, twelve villagers, romance and marriage, the
notice-board requests, the Collection and Help tabs, three save slots, Options,
and Web/Windows/Linux demo builds.

## 0.2.0-alpha — Phase 2: Alpha
A full first year is playable: four seasons, weather, festivals, friendships,
foraging on the Ghats Trail, fishing, the Panchayat Hall, the journal and the
year review.

## 0.1.0 — Phase 1: Vertical Slice
A playable Ugadi (Spring) season with the title screen, the Farm and the
Town, nine crops, the shop, villagers, the day summary and saving.

## 0.0.1 — Phase 0: Foundations
The core loop: till, plant, water, harvest and ship.
