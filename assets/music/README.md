# PSZ Music

Music from Phantasy Star Zero Original Soundtrack.  
Source: https://www.youtube.com/playlist?list=PLEBBBFcAycEjYhgzGw4LUVD3qwZzlAbQF

## Track Mapping

| Area | Track Name | Playlist # | Filename |
|------|-----------|------------|----------|
| Title Screen | Phantasy Star Zero | 26 | phantasy_star_zero.ogg |
| Dairon City | Full of Life | 04 | full_of_life.ogg |
| Mayor's Office | General | 05 | general.ogg |
| Teleporter | Flowing | 28 | flowing.ogg |
| Valley A | Desolate Scape | 07 | desolate_scape.ogg |
| Valley B | Desolate Wilds | 09 | desolate_wilds.ogg |
| Valley Boss | Growl, From The Red Beat | 13 | growl_from_the_red_beat.ogg |
| Wetlands A | Damp Swamp | 16 | damp_swamp.ogg |
| Wetlands B | Damp Clump | 17 | damp_clump.ogg |
| Wetlands Boss | Chaotic Swells | 20 | chaotic_swells.ogg |
| Snowfield A | Snowflake | 21 | snowflake.ogg |
| Snowfield B | Snowstorm | 22 | snowstorm.ogg |
| Snowfield Boss | Rush to Struggle | 44 | rush_to_struggle.ogg |
| Paru A | Secret Alter | 33 | secret_alter.ogg |
| Paru B | Secret Ritual | 34 | secret_ritual.ogg |
| Paru Boss | Machinery Pressure | 38 | machinery_pressure.ogg |
| Makara Ruins A | Trickle Maze | 40 | trickle_maze.ogg |
| Makara Ruins B | Trickle Labyrinth | 41 | trickle_labyrinth.ogg |
| Makara Ruins Boss | Rush to Struggle | 44 | rush_to_struggle.ogg |
| Arca Plant A | Overflow | 49 | overflow.ogg |
| Arca Plant B | Overdrive | 50 | overdrive.ogg |
| Arca Plant Boss | Machinery Conqueror | 53 | machinery_conqueror.ogg |
| Dark Shrine A | Crescent Serenade | 55 | crescent_serenade.ogg |
| Dark Shrine B | Crescent Crusade | 56 | crescent_crusade.ogg |
| Dark Shrine Boss 1 (MT) | "IDOLA" The Imitated God | 59 | idola_the_imitated_god.ogg |
| Dark Shrine Boss 2 (DF) | "IDOLA" The Devil's Shadow | 60 | idola_the_devils_shadow.ogg |

## Download

Files are OGG Vorbis format. Download from YouTube playlist with:

```bash
yt-dlp --cookies-from-browser chrome \
  --playlist-items 4,5,7,9,13,16,17,20,21,22,26,28,33,34,38,40,41,44,49,50,53,55,56,59,60 \
  -x --audio-format vorbis \
  -o "assets/music/%(playlist_index)02d_%(title)s.%(ext)s" \
  "https://www.youtube.com/playlist?list=PLEBBBFcAycEjYhgzGw4LUVD3qwZzlAbQF"
```

Then rename files to match the filenames above.
