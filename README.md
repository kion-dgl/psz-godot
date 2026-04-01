# PSZ Godot

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

## Credits

- **Character Portraits** by Rozalin#4270 — class artwork for character creation
- **Input Prompts** by [Kenney](https://www.kenney.nl/) — CC0 (public domain)
  - [kenney.nl/assets/input-prompts](https://kenney.nl/assets/input-prompts)
