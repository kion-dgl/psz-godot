# Office review preview

From the repository root, export the current procedural geometry:

```sh
godot --headless --path . --script res://scripts/tools/office_web_export.gd
```

The before/after/detail tabs use local captures in
`web/public/office-preview/{before,after,angle}.png`. Keep `before.png` as the
baseline. Refresh the current captures with `scenes/tools/office_screenshot.tscn`
and copy `user://office_shot.png` and `user://office_shot_angle.png` to
`after.png` and `angle.png` respectively. Generated assets are gitignored.

Start the existing web development server:

```sh
cd web
npm run dev -- --host 127.0.0.1 --port 5173
```

Open http://127.0.0.1:5173/psz-godot/office-preview.html.
The 3D view uses the exported Godot geometry and embedded textures. Lighting is
approximated in Three.js; the image tabs show actual Godot output.

Original-game reference assets shown below the viewer:

- `reference-sun.png`: `assets/stages/city_e/s00e_sa3/lndmd/s00_0_mark02.png`
- `reference-trim.png`: `assets/stages/city_e/s00e_sa2/lndmd/s00e_sa2_m_s00_0_waku.png`
- `reference-stone.png`: `assets/stages/city_e/s00e_sa2/lndmd/s00_0_wpwall03.png`
- `reference-game.png`: the user's supplied DS emulator screenshot (two views of
  the same top screen).

Copy these into the generated preview directory when recreating the local
reference gallery. The sun's circular detail is UV-mapped from the original
half-panel atlas; the screenshot, rather than the similarly named octagonal
`mark03` texture, determines which decoration to use.

The current architectural pass follows the emulator's raised rear landing,
central six-step stair, timber railings and tall bookcases with four decorative
ladders. The comparison baseline is the preceding low-dais version. To verify
walkability and Principal interaction using the actual player:

```sh
godot --headless --path . res://scenes/tools/office_walkthrough.tscn
```

This checks the floor collision, walks up the stairs, opens and dismisses the
Principal's dialog, and walks back down. Run from the repository root.
