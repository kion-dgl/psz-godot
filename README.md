# PSZ Godot

[![CI](https://github.com/kion-dgl/psz-godot/actions/workflows/ci.yml/badge.svg)](https://github.com/kion-dgl/psz-godot/actions/workflows/ci.yml)
[![Release](https://github.com/kion-dgl/psz-godot/actions/workflows/release.yml/badge.svg)](https://github.com/kion-dgl/psz-godot/actions/workflows/release.yml)

**Phantasy Star Zero — if it were actually like PSO.**

A fan-made action RPG built in Godot 4.5, inspired by Phantasy Star Online and Phantasy Star Zero. Explore instanced quest areas, fight enemies with real-time melee and ranged combat, cast techniques, and gear up across 14 character classes.

> This is a fan project and is not affiliated with SEGA.

## Play

Download the latest build from [Releases](https://github.com/kion-dgl/psz-godot/releases/latest).

## Web Tools

Quest editor, stage viewer, and animation storybook are available at:
**https://kion-dgl.github.io/psz-godot/**

## Features

- **Combat** — Melee combos (saber, sword, daggers, spear, rod, wand), ranged weapons (handgun, rifle, mechgun), and technique casting (Foie, Barta, Zonde + Gi/Ra variants)
- **14 Classes** — Hunters, Rangers, and Forces with PSU-style archetypes, innate weapon bonuses, and technique limits
- **Quests** — Instanced field areas with gated rooms, enemy spawns, and boss encounters
- **NPCs & Shops** — City hub with weapon, item, technique, and crafting shops
- **Action Palette** — PSO-style configurable action bar with swappable pages

## Project Structure

- `scenes/` — Godot scenes (2D menus, 3D field/city areas)
- `scripts/` — GDScript game logic
- `assets/` — Models, textures, animations, UI assets
- `data/` — Game data (quests, enemies, items, stage configs)
- `web/` — React development tools (quest editor, stage editor, storybook)

## Building from Source

Requires [Godot 4.5+](https://godotengine.org/download/).

```bash
git clone https://github.com/kion-dgl/psz-godot.git
cd psz-godot
# Open in Godot editor, or export from command line
```

### Web Tools (development)

```bash
cd web && npm install && npm run dev
```

## Quest Tracker (Alpha)

### Story Missions

| # | Quest | NPCs | Area | Boss | Status |
|---|-------|------|------|------|--------|
| 1 | Search and Rescue | Kai, Sarisa | Valley | -- | Implemented |
| 2 | Poisoned Water | -- | Wetlands | Octo Diablo | Not started |
| 3 | Finding Ogi | -- | Snowfield | Hildegahna | Not started |
| 4 | Messages from the Past | Mira, Elio | Paru | TBD | Implemented (needs boss) |
| 5 | Rescue at Makara | Kai | Makara Ruins | Rohjade | Not started |
| 6 | Arca Plant A | -- | Moon Base | Humilias (Reve's mech) | Not started |
| 7 | Arca Plant B | -- | Moon Industrial | Mother Trinity | Not started |
| 8 | Dark Shrine | Kai | Dark Falz Domain | Dark Falz (Kai vessel) | Not started |

### Side Quests

| # | Quest | NPCs | Area | Boss | Status |
|---|-------|------|------|------|--------|
| S1 | The Paru Pact | Elio | Paru | -- | Implemented (no enemies) |
| S2 | Apothecary's Supply | Fern | Wetlands | -- | Implemented |
| S3 | Static in the Snow | Dr. Carlo, Kai | Snowfield | -- | Implemented |
| S4 | Deep Ore Extraction | Dorn | Valley | -- | Implemented |
| S5 | Native Research | Dr. Carlo | Valley+Wetlands+Snowfield | -- | Implemented |
| S6 | Seek My Mentor | Ren | Makara Ruins | -- | Implemented |
| S7 | Claiming a Stake | -- | Valley | Dragon | Not started |

### Alpha Checklist
- [ ] All story missions completable end-to-end
- [ ] All side quests completable end-to-end
- [ ] Enemies spawn on floor (not floating)
- [ ] NPC dialog triggers working in field
- [ ] Boss encounters: Octo Diablo, Dragon, Hildegahna, Rohjade, Humilias, Mother Trinity, Dark Falz
- [ ] Companion NPCs follow player in field
- [ ] Quest items collectible and tracked
- [ ] Moon areas: Arca Plant A (robot base), Arca Plant B (industrial), Dark Shrine (surreal)
- [ ] Kai corruption arc: normal → changed after Makara → Dark Falz vessel in Dark Shrine

## Credits

- **Character Portraits** provided by Rozalin#4270
- **Input Prompts** by [Kenney](https://www.kenney.nl/) — CC0 (public domain)
  - [kenney.nl/assets/input-prompts](https://kenney.nl/assets/input-prompts)
