# Megacorp Simulator: FreeSynd analysis and Ada/browser porting plan

## Changelog

### 2026-11-10 — version 0.8.0, item 8

Our own code is MIT, copyright Robert Boettcher. The imported FreeSynd trees and `megacorp/COPYING` are gone from this revision. Git history is unchanged.

`Megacorp.Weapons` is a small table: pistol, SMG, and rifle, each with reach, damage, ticks between shots, and a magazine. A ped has health (100) and an ammo count. `Megacorp.Shots` rolls a hit on a child RNG stream and walks a Bresenham line; a building tile between the ends blocks the shot. `Shoot_At` aims for one tick, then fires at the weapon's rate until the target is down, out of reach, blocked, or out of ammo. A downed ped stops and that ped's queue is cleared.

`bin/megacorp --export` adds a firefight to seeds 1, 42, and 100. The page draws the shot line, a health bar, and the ammo count from that trace. It does not roll dice.

### 2026-11-10 — version 0.7.0, item 7

`Megacorp.Actions` is a fixed-capacity queue on each ped. The actions are `Walk_To` a tile, `Wait` a number of ticks, `Turn_To` one of eight directions, `Follow` another ped, and `Pick_Up` an item that sits on a tile. Each tick runs the front action. When it is done, the next action starts on the following tick. When it fails, the rest of the queue is cleared and the ped stands. `Walk_To` and `Follow` use `Megacorp.Peds`, so peds still block each other and the higher id can repath. An order either replaces the queue or appends to it, and takes effect on the next tick. The capacity is 8, checked by a precondition.

`bin/megacorp --export` adds a scripted mission to seeds 1, 42, and 100. One ped walks, waits, turns, follows a second ped along that ped's own walk, then picks up a case. Each tick of the trace stores the current action and the remaining queue. The page shows that beside the tick counter and draws the case until the pickup. It does not run the queue.

### 2026-11-10 — version 0.6.1

The browser page sets `crossOrigin = "anonymous"` before drawing the atlas, and if `getImageData` throws (WebKit on raw.githack.com reports `SecurityError: The operation is insecure.`), hover uses the tile diamond instead of the atlas alpha. That read no longer skips loading the map.

### 2026-11-10 — version 0.6.0, item 6

`Megacorp.Peds` walks a `Megacorp.Path` route on a fixed tick. A ped stores the tile it stands on, an integer count of sub-tile steps toward the next tile (`Steps_Per_Tile` is 8; 0 is the centre), an 8-way facing, a speed in sub-tile steps per tick, and a state: `Standing`, `Walking`, or `Arrived`. There is no floating point. Each tick moves the ped along the route and sets facing from the step it is taking.

Peds block each other. A ped occupies its current tile, and also the next tile once a crossing has started. Ticks are applied in ascending ped id, so two peds cannot both claim one free tile. If the next tile is taken, the ped waits. After three ticks the ped with the greater id repaths from where it stands, and that one search treats the other peds' tiles as blocked. The lower id keeps its route. That is enough for two peds meeting in a corridor that has a side tile: they never share a tile, and both arrive. The same run twice is the same trace.

`Path.Find` can take an extra set of blocked tiles for that repath. The start tile is not treated as blocked. `bin/megacorp --export` writes a per-tick trace for the prepared walk on seeds 1, 42, and 100, and a two-ped meeting on a 5×3 map (`encounter.json`). The browser page plays, pauses, and steps that trace and draws a marker with a facing stroke in both views. It does not simulate.

### 2026-11-10 — version 0.5.0, item 5

`Megacorp.Path` searches the city grid with A*. Walk steps need the walkable flag. Drive steps need the drivable flag (roads in the test layout). Movement is 8-way. A diagonal is allowed only when both orthogonal tiles it crosses are passable, so a search cannot cut a blocked corner. Orthogonal cost is 10 and diagonal cost is 14, both integers. The octile heuristic matches those costs. When two nodes share a score, the smaller heuristic wins, then the smaller Y, then the smaller X, so one map and one pair of endpoints produce one path. The result is `Found` with the tile list, `No_Path`, or `Budget_Exceeded` when the expansion budget runs out. The default budget is 65536 node expansions.

`bin/megacorp --export` adds three prepared queries to each of seeds 1, 42, and 100: a walk across the blocks, a drive along the roads, and a walk whose goal is water. The browser offers those queries in a menu and snaps a click to the nearest prepared endpoint. It draws the stored path. It does not search.

### 2026-11-10 — version 0.4.0, item 4

`Megacorp.Data.Virtual_FS` is a read interface: `Exists`, `Read`, and `List` by a logical path such as `assets/tiles.json`. `Virtual_FS.Native` is the disk backend and the only place asset reads call the host file system. A later WASM host can implement the same `Backend` with OPFS or fetch.

The placeholder tileset is original art from `tools/gen_tileset.py` (flat-shaded isometric diamonds and building stacks, one sprite per terrain and height). It is stored as `web/assets/atlas.png` plus `web/assets/tiles.json`, with `web/assets/LICENCE.txt`. `Megacorp.Assets.Placeholder` loads that index through the virtual file system. Tile id is `Terrain'Pos * 16 + height`. Map export writes that id in each cell. The browser draws the id from the atlas; it does not choose the sprite itself. The page toggles between the flat view and an isometric view (back to front, buildings stacked in the sprite). Hover in the isometric view uses the atlas alpha so a tall building is the tile under the cursor.

### 2026-11-10 — version 0.3.0, item 3

`Megacorp.Map` holds one city. The size comes from `Megacorp.Parameters` (default 128×128, each edge at most 1024). A tile has a terrain (`open`, `road`, `pavement`, `building`, `water`), a height 0..15, and stored walkable and drivable flags. Accessors are bounds-checked. Four- and eight-neighbour steps are there for pathfinding later (X east, Y south, origin 1).

`Test_Layout` is not the city-block generator. It is a seeded stand-in: open ground, a wandering river, a road grid (roads replace water, so the crossing reads as a bridge), pavement beside roads, and building blocks whose height comes from the city-1 child of the world seed. The same seed rebuilds the same map. The headless executable prints a northwest sample and a window on the river for seed 42.

The browser page does not run Ada. GNAT-LLVM/AdaWebPack is not set up on this machine, so the executable writes JSON (`--export DIR`) and `web/` only draws it. `./build.sh` regenerates `web/data/`. The page is [web/index.html](../web/index.html), and once this is on `master` it is at `https://raw.githack.com/RobertBoettcherSF/ADA-Megacorp-Simulator/master/web/index.html`.

### 2026-11-10 — version 0.2.0, item 2

`Megacorp.RNG` is implemented. The generator is **xoshiro256\*\*** (Blackman and Vigna, 2018, public domain). A 64-bit seed is expanded with **SplitMix64** (Vigna, 2015, the fixed-increment form of Java 8's SplittableRandom). Both are unsigned 64-bit integer arithmetic only: no `Ada.Numerics` generators and no floating point in the state, so the same seed yields the same stream on native GNAT and, later, on WebAssembly.

Child streams are not jumps of a parent cursor. `Derive (Parent, Key)` is SplitMix64's mix function applied to `Parent + 16#9E37_79B9_7F4A_7C15# * Key`. The mix is a bijection and the multiplier is odd, so distinct keys from one parent produce distinct child seeds. `Child` reads the parent's origin seed, not how far that generator has been drawn, so re-deriving one region leaves every other stream where it was. Domain keys are `Domain'Pos * 2**32 + Index` with `Domain` ordered `World`, `Region`, `City`, `Block`, `Mission`. A later generator version can be folded into the key when unvisited regions are re-rolled.

Reference vectors, checked by the smoke test:

- xoshiro256\*\* state `(1, 2, 3, 4)`, first four outputs (the sequence published with the Rust `rand_xoshiro` reference test, produced from the reference C): `16#0000_0000_0000_2D00#`, `0`, `16#0000_0000_5A00_7080#`, `16#10E0_0000_0000_9D80#`.
- SplitMix64 started at 0, first four outputs, which are also the state words of `Make (0)`: `16#E220_A839_7B1D_CDAF#`, `16#6E78_9E6A_A1B9_65F4#`, `16#06C4_5D18_8009_454F#`, `16#F88B_B8A8_724C_81EC#`.
- `Make (0)` then `Next`, four times: `16#99EC_5F36_CB75_F2B4#`, `16#BF6E_1F78_4956_452A#`, `16#1A5F_849D_4933_E6E0#`, `16#6AA5_94F1_262D_2D2C#`.

Sources: [xoshiro256starstar.c](https://prng.di.unimi.it/xoshiro256starstar.c), [splitmix64.c](https://prng.di.unimi.it/splitmix64.c).

## Autonomous decisions (night of 2026-11-10)

Robert authorised items 8 through 28 to be built overnight, one branch and one minor version each, and asked for this log so the choices can be reviewed in the morning. Standing calls for the whole night: skip item 12 (the C++ comparison harness) and record that skip when its turn comes; if GNAT-LLVM or AdaWebPack cannot be built for item 20, use an Ada WebSocket server and record that; item 27 uses generated placeholder sounds.

### Item 8 — licence, weapons, and shots

**Licence.** MIT for `megacorp/`, `web/`, `tools/`, and `docs/`. Copyright line: Robert Boettcher. File headers are `SPDX-License-Identifier: MIT`. A root `LICENSE` and a root `README.md` replace the old layout. `megacorp/COPYING` is deleted.

**Removed trees.** `freesynd/`, `freesynd-experimental/`, `libsyndicate-0.13/`, `libs/`, `scripts/`, and `www/` are deleted in this revision. There was no other top-level FreeSynd file (no root README, COPYING, or CMake file). Git history is not rewritten, so older commits still contain those files.

**Copy check.** Before the deletion, a search of `megacorp/`, `web/`, `tools/`, and `docs/` found no code, data table, or numeric constant copied from those trees. The only mentions were this design document and comments that said we do not ship original game data. The RNG test vectors are the published xoshiro256** and SplitMix64 sequences. Orthogonal cost 10 and diagonal cost 14 are the usual integer octile pair. Nothing was rewritten because nothing had been copied. The sentences that told us to keep FreeSynd in the tree as a logic reference now say it was a design inspiration only.

**Weapons.** Pistol: reach 8, damage 25, 4 ticks between shots, 12 rounds. SMG: 6, 10, 2, 30. Rifle: 14, 40, 6, 8. These numbers are new. The alternative was to mirror some other game's weapon table; that was rejected.

**Health and a downed ped.** Health starts at 100. At 0 the ped is down, movement stops, and that ped's queue is cleared.

**Range and line of sight.** Reach is Chebyshev distance, so a diagonal step counts as one. The line is Bresenham. A building tile strictly between the two ends blocks the shot. Roads, pavement, open ground, and water do not. The alternative was to block every non-walkable tile, which would also stop shots across water.

**Hit roll.** Chance is 100 at distance 0 or 1 and 40 at the weapon's reach, linear in between, integer division. The roll is `RNG.Chance` on a fresh child of the fight seed (`Mission` domain, key = ped id × 1000 + shot number). A hit deals the weapon's damage exactly. A second damage roll was the alternative; it was left out so the smoke test can check an exact total.

**Shoot_At.** One tick of aiming, then a shot every `Rate` ticks. Out of reach, a blocked line, or an empty magazine fails the action before spending a round when the shot cannot be made, and fails it after the last round when the magazine runs out with the target still up. Downing the target completes the action. Failure clears the rest of that shooter's queue, same as the other actions.

**Page.** Seeds 1, 42, and 100 gain a Firefight trace. The page draws a solid red line for a hit and a dashed line for a miss, a health bar, and ammo next to the tick. The older walk, path, meeting, and scripted-mission views stay.

### 2026-11-10 — Robert's decisions (override anything later in this document that conflicts)

1. **Language and route.** All logic, and as much of the rest as possible, in plain Ada. JavaScript is only a thin browser layer (canvas, audio, input, storage). The Ada core is built natively first with GNAT 12.3 and gprbuild, and later compiled to WebAssembly (GNAT-LLVM / AdaWebPack). A WebSocket server is the fallback.
2. **Own setting and own IP.** Distinct Megacorp names and own placeholder art. No original Syndicate data, ever. Dropped old item 5 (CRC/RNC loaders for original data) and old item 29 (classic original maps). `Megacorp.Assets.Syndicate` is not part of the package map.
3. **Contracts, not SPARK.** `Pre` / `Post`, `Type_Invariant`, and `Assert`, compiled with `-gnata`, from the first commit. No SPARK for now.
4. **Scale is a generator parameter.** Default 4 megacorporations, about 40 world regions, city maps about 128×128 tiles. The 0.1.0 skeleton accepts corporations 1..16, regions 1..512, and a city-map edge 1..1024, with those defaults.
5. **Persistence.** Scenario worlds are locked once generated. In free play and auto-play, unvisited regions may be re-rolled; visited regions stay as left.

Items below are renumbered **1–28** after those two drops. "Own IP" here is the setting and the art (old question 7), not a choice of software licence. The licence tag (old question 12) is still open; the 0.1.0 skeleton uses GPL-2-or-later headers, matching FreeSynd's file headers and item 1, until that choice is closed.

**Status:** agreed design, updated 10 November 2026. Items 1–8 (version 0.8.0) are implemented under `megacorp/`. The browser check page is `web/`. The code we wrote is MIT.  
**Date:** 10 November 2026, Europe/Berlin  
**Source repo:** https://github.com/RobertBoettcherSF/ADA-Megacorp-Simulator (branch `master`, commit `fa08136b239dbcbb0370a73ef7df4420d3834513`)  
**Last upstream FreeSynd work:** 19 February 2015, 07:44 Europe/Berlin (`Rework action for police : finished.`, author benblan)  
**Target:** all game logic in plain Ada; a thin JavaScript browser layer; world **procedurally generated** from a seed and **persistent** across sessions. Own setting, own placeholder art, no original Syndicate data.

This document is the agreed design. It covers (1) a historical inventory of a FreeSynd tree that used to be imported, (2) the target Ada core and browser architecture, including a seeded procedural world and its save model, (3) a numbered list of small, testable implementation items, and (4) the decisions above plus the questions still open.

That imported tree was a design inspiration only. It was removed in 0.8.0. This repository no longer contains FreeSynd code or files. Later work, if it needs a reminder of how this kind of game usually behaves, uses the general public design of that kind of game. The inventory below records what was once here; the line counts were measured before the deletion.

---

## 1. Recommendation (short)

Base the port on `freesynd/branches/rework-actions` (53,488 C/C++ lines in 186 files), not `freesynd/trunk` (49,076 lines, frozen 4 November 2013, 18:59 Europe/Berlin) and not `freesynd-experimental` (a separate, incomplete C+Lua experiment of about 2,459 C/header lines plus 731 lines of Lua).

Build a **headless, deterministic Ada simulation core** first, tested with GNAT 12.3 + gprbuild. As much of the program as possible stays plain Ada. JavaScript is only the thin browser layer: canvas, audio, input, and storage. Drive that layer by compiling the same core to WebAssembly (GNAT-LLVM + AdaWebPack, state as of mid-2026). Fallback: the same core as a local native WebSocket server. Contracts (`Pre` / `Post`, `Type_Invariant`, `Assert`, `-gnata`) are on from the first commit. SPARK is not in the plan for now.

The world is **not** a playback of FreeSynd’s fixed `MAPxx.DAT` / `GAMExx.DAT` files, and those files are not a feature. Ada generates regions, cities, mission blocks, peds, and corporations from a master seed. Defaults, all overridable generator parameters: **4** megacorporations, **about 40** regions, city maps **about 128×128** tiles. Persistence stores that seed plus a versioned snapshot (and a short delta since the last snapshot) of everything that changed. Scenario worlds are locked once generated. In free play and auto-play, unvisited regions may be re-rolled; visited regions stay as left. In the browser, saves live in OPFS (IndexedDB as fallback). Art is an own placeholder pack. Original Syndicate data is not loaded, not shipped, and not optional.

FreeSynd’s transferable core is the **simulation vocabulary**: isometric tile maps, walkability and pathfinding, peds and action queues, behaviour components, weapons/shots, vehicles, mission objectives, research, and the between-mission economy. Map *content* is generated; combat and AI still run on the same kinds of objects. Names, story, and art are Megacorp’s, not Syndicate’s.

---

## 2. Inventory of the imported tree

### 2.1 Top-level folders

| Folder | Role | Notable measured size |
|---|---|---|
| `freesynd/` | Full FreeSynd SVN import: `trunk`, `tags/release-0.5`…`0.7.1`, `branches/rework-actions` | Inflated if summed: 420 `.cpp` / 192,669 lines and 509 headers / 69,771 lines **across all trees** |
| `freesynd-experimental/` | Abandoned C+Lua rewrite (mythological filenames: tiamat, gaia, hugin…). SDL + Lua 5.1 + SDL_mixer. Notes on tiles, pathfinding, scripting. Last touched 16 April 2011, 11:16 Europe/Berlin | 13 `.c` / 2,263 lines; 2 headers / 196; 5 Lua / 731; 1 Python helper |
| `libsyndicate-0.13/` | Paul Chavent’s library for *reading* Syndicate data files (maps, sprites, RNC, palettes). Autotools, no game loop. WTFPL original, relicensed GPL-2 in FreeSynd’s README | Library proper: 22 `.cc` / 1,303 lines + 24 headers / 1,623. Tests/demos/tools add more (one generated test header is 12,711 lines) |
| `libs/MSVC/` | Bundled Windows binaries and headers for the MSVC build | SDL 1.2, SDL_image, SDL_mixer, libpng, zlib, ogg/vorbis DLLs + 49 headers / 20,613 lines |
| `scripts/` | `cpplint.py`, website update script | 3,055 lines (almost all cpplint) |
| `www/` | Project website (PHP) | 11 PHP / 1,203 lines; not part of the game |

Git history on `master`: 972 commits, 10 May 2006 through 19 February 2015. There is **no Ada** in the tree.

### 2.2 Which FreeSynd tree to base on

| Tree | Last change (Europe/Berlin) | C/C++ files | Physical lines | What it is |
|---|---|---|---|---|
| `tags/release-0.5` | — | 121 | 31,873 | Old release snapshot |
| `tags/release-0.6` | — | 141 | 38,432 | Old release snapshot |
| `tags/release-0.7` | — | 152 | 44,558 | Old release snapshot |
| `tags/release-0.7.1` | — | 155 | 45,295 | Old release snapshot |
| `trunk` (README: FreeSynd 0.7.5) | 4 Nov 2013, 18:59 | 179 | 49,076 | Last “mainline” snapshot; then work moved to the branch |
| `branches/rework-actions` | 19 Feb 2015, 07:44 | 186 | 53,488 | **Recommended base** |

`rework-actions` is 15 months newer than trunk. Unique to the branch: `src/ia/action.cpp` (1,006 lines) and `ia/actions.h` (616), `ia/behaviour.cpp` (412) and `ia/behaviour.h`, plus extracted `model/shot.*` and `model/train.*`. Ped, mission, and pathfinding files grew (e.g. `ped.cpp` 2,750 → 3,184). Police, panic, and persuasion were reworked as `BehaviourComponent`s; trains vs drivable cars were distinguished. It is still unfinished (0.7.5 notes already said agent AI was partial, pathfinding needed work, map drawing was buggy, and not every weapon was correct). That is still the best starting point, because the AI/action split is the shape the Ada packages should take.

`freesynd-experimental` is not a later FreeSynd. It is a from-scratch experiment and is not a better base.

`libsyndicate` is a **data-format reference** (and has a Latex format document under `doc/`). Useful when writing Ada loaders for original assets; it is not an engine.

### 2.3 Subsystems in `rework-actions/src` (186 files, 53,488 lines)

Classification is by file role, not by a perfect isolation of logic from SDL (see §5).

| Subsystem | Files | Lines | Main units |
|---|---|---|---|
| Peds / AI / actions | 12 | 10,903 | `ped.cpp` 3,184, `pedpathfinding.cpp` 2,755, `pedactions.cpp` 1,070, `ia/action.cpp` 1,006, `ia/behaviour.cpp` 412 |
| Menus + in-game HUD/renderers | 41 | 10,852 | `gameplaymenu.cpp` 1,507, `selectmenu.cpp` 825, widget/minimap/map renderers |
| Mission / map engine | 15 | 9,094 | `mission.cpp` 3,197, `mapobject.cpp` 1,755, `missionmanager.cpp` 1,024, `map.cpp` ~300+, `model/leveldata.h` 395 |
| Weapons / shots | 8 | 3,480 | `weapon.cpp` 1,296, `model/shot.cpp` 638, `weaponmanager.cpp` |
| Rendering (gfx) | 18 | 3,270 | Screen, sprites, tiles, fonts, FLI player, dirty list |
| App / config / IPA glue | 13 | 2,290 | `app.cpp` 780, `freesynd.cpp` , IPA timers |
| Sound/music (minus SDL_mixer wrappers) | 10 | 2,067 | `xmidi.cpp` 873, managers, VOC/TAB loaders |
| World map / session / agents | 8 | 1,992 | `gamesession.cpp` 621, `gamecontroller.cpp`, agent manager |
| Editor / dump tool | 16 | 1,917 | Optional; not required for the port |
| Data-file I/O utils | 10 | 1,779 | `dernc.cpp` 325 (RNC-1), CRC32, `file.cpp`, `portablefile.cpp` |
| Other utils | 10 | 1,643 | log, utf8, timer, config, seqmodel |
| Research / mods | 9 | 1,549 | `researchmanager.cpp` 458, `research.cpp` 272, mod manager |
| Vehicles | 4 | 1,136 | `vehicle.cpp` 878, `model/train.*` |
| Platform (SDL video/audio/input) | 7 | 1,132 | `system_sdl.cpp` 491, `system.h` abstract interface, SDL_mixer backends |
| Core other + build tools | 5 | 384 | squad, game events, embed tool |

Largest single files are also the porting risk: mission, peds, pathfinding, map objects, gameplay menu, weapons.

Trunk `src/` layout (for comparison): root 51 files / 23,556 lines; `menus/` 41 / 10,852; `gfx/` 18 / 3,270; `utils/` 20 / 3,415; `sound/` 14 / 2,466; `core/` 14 / 2,857; `editor/` 15 / 1,310; `model/` 4 / 1,215. The branch adds `src/ia/`.

---

## 3. External dependencies and build

FreeSynd 0.7.5 builds with **CMake ≥ 2.6** (`freesynd/trunk/CMakeLists.txt` and the same structure on the branch). Defines `SYSTEM_SDL`. Finds:

| Library | Version in `libs/MSVC/include` (bundled Windows build) | Role |
|---|---|---|
| SDL | 1.2.14 | Window, 8-bit surface, events, timer |
| SDL_image | 1.2.10 | Cursor PNG (`data/cursors/cursors.png`) |
| SDL_mixer | 1.2.11 | Sound samples and music (Ogg or converted XMI) |
| libpng | 1.4.1 | PNG; used with SDL_image |
| zlib | bundled (`zlib1.dll`) | PNG/compression |
| libogg / libvorbis | bundled DLLs | Ogg music (`data/music/*.ogg`) |

Linux/macOS expect the same libraries from the system (SDL 1.2 frameworks on macOS). The Ada port does **not** need to keep SDL. The browser front end replaces video, audio, input, and filesystem. A native test harness can stay headless.

CMake also embeds `freesynd.ini`. Debug builds compile a `dump` / editor binary (`src/editor/`, `dump.cpp`).

`freesynd-experimental` is a raw Makefile: `sdl-config`, `-llua5.1 -lSDL -lSDL_mixer`.

---

## 4. Game data and licensing

### 4.1 Two classes of files

**A. FreeSynd’s own data** (can be shipped with a GPL build): `data/lang/*.lng`, `data/ref/weapons.dat` (302 lines, 14 weapons), `data/ref/research.dat` (88 lines), `data/ref/original_data.crc`, `data/cursors/cursors.png`, `data/music/intro.ogg` and `assassinate.ogg`.

**B. Original 1993 Syndicate `DATA` files** (copyrighted; **not** in this repo). INSTALL and the website are explicit: you must own the first Syndicate (not Syndicate Plus, not Syndicate Wars). At first run, FreeSynd CRC32-checks files listed in `original_data.crc`.

Active CRC entries: **382** (plus 2 commented DLLs). Breakdown:

- 60× `GAMExx.DAT` (levels: game01–50 and game90–99)
- 59× `MAPxx.DAT` (tile maps; numbering has gaps, e.g. no map14)
- 200× `MISSxx.DAT` (mission text: 50 English + 50 each for French `miss1xx`, Italian `miss2xx`, German `miss3xx`)
- 63 named assets: tiles (`hblk01.dat`, `col01.dat`), sprites/anims (`hspr-0.dat/.tab`, `hele-0.ani`, `hfra-0.ani`, `hsta-0.ani`, pointers, menu sprites), palettes, fonts, intro/menu FLI (`intro.dat`, `mtitle.dat`, `mmap.dat`, …), sound (`sound-0/1.dat/.tab`, `isnds-*`, `sample.ad/.opl`), music (`intro.xmi`, `syngame.xmi`)

Many of those files are **RNC-1** compressed (signature `0x524E4301` / `"RNC\001"`). `File::loadOriginalFile` unpacks them via `utils/dernc.cpp`. Case-insensitive names (lower then upper).

### 4.2 Licence implications (must stay visible)

- **FreeSynd engine:** GNU GPL version 2 (README/COPYING). File headers usually say “version 2 or later”. An Ada rewrite of this code must be GPL-2 (or 2-or-later, to be decided) and cannot relicense the ported logic as proprietary.
- **libsyndicate:** originally WTFPL (Paul Chavent, 2010); FreeSynd’s README says it was re-licensed GPL-2 for use in the project.
- **Original Syndicate assets:** copyright Bullfrog / Electronic Arts. They must **never** be bundled, cached on a public server, committed, or loaded, including from a user-supplied folder. Megacorp does not read them.
- The inventory above is documentation of the imported FreeSynd tree, not a loader specification.

### 4.3 How procedural generation changes the data dependency

**Decision (2026-11-10):** one asset mode. An own placeholder pack (tiles, palettes, ped and vehicle sprites, UI chrome, sound) under a free licence. Enough to play a generated world. There is no user-supplied Syndicate `DATA` mode and no classic `MAPxx` / `GAMExx` / `MISSxx` mode. CRC/RNC loaders for original files are not on the list (old item 5, dropped). Classic original maps are not on the list (old item 29, dropped).

The loader is an abstract **asset pack** of named blobs. The simulation never opens `MAP01.DAT`.

What still transfers from FreeSynd as *ideas*, rewritten in Ada against placeholder art: pathfinding and walk *rules* (FreeSynd’s column types become a tileset contract we define), ped types and behaviour, action and weapon timing (an own weapon table; FreeSynd’s `weapons.dat` is a reference for ideas, not a file we ship), research tree, session/economy, isometric draw order. What does **not** transfer as content: the hand-authored maps, the scripted missions, the fixed country layout, and every original sprite, tile, palette, and sample.

---

## 5. Logic vs platform split

FreeSynd already has a `System` singleton (`system.h`) intended as the port seam: `initialize`, `updateScreen`, `pumpEvents`, `delay`, `getTicks`, palette and cursor calls, mouse position. `SystemSDL` implements it with SDL 1.2. The seam is real but leaky: `App::run` calls `SDL_GetTicks` / `SDL_Delay` directly; audio goes through `SDLMixerMusic` / `SDLMixerSound`; `File` uses `fopen` and OS paths.

| Keep as portable Ada (simulation + content) | Replace with the browser (or a test host) |
|---|---|
| Map grid, walkability, pathfinding | Window, Canvas present, palette → RGBA |
| Peds, actions, behaviour, persuasion, panic, police | Pointer and keyboard events |
| Weapons, shots, damage, explosions | WebAudio output |
| Vehicles / trains | User file picker; OPFS / IndexedDB |
| Mission start/tick/objectives | rAF / fixed-step scheduler (calls into Ada) |
| World / corps / tax / research / agents | Optional: WebSocket transport if the server fallback is used |
| Generators (world, city, block) | — |
| Save format (seed + snapshot + delta) | Storage *backend* only |
| Sprite/tile *decode* and isometric *draw order* (and an 8-bit 640×400 framebuffer if we keep that model) | Blit of that buffer (or a display list) to the page |
| Placeholder asset decode (no RNC, no CRC, no original parsers) | — |
| Own audio assets | Mixing and playback in the browser |

Screen constants in `common.h`: menus 320×200, game view 640×400, 8-bit paletted. `GameplayMenu::handleTick` runs object `animate(diff)` when more than 33 ms have accumulated. The app loop aims at a 30 ms frame (`SDL_Delay` if under 30 ms). Time is wall-clock and variable-dt today. The Ada core will use a **fixed tick** (33 ms, or 10 ms with interpolation later) injected by the host so tests and net/wasm play stay deterministic.

`rand()` is used for shot spread, civilian wander, tax/population jitter, and enemy syndicate moves. `freesynd.cpp` seeds with `time(NULL)` / `GetTickCount()`. The Ada core must use an explicit, seeded PRNG; never libc `rand`.

**Save-format bug to not copy:** `App::saveGameToFile` writes major=1, minor=2, but `loadGameFromFile` rejects `minorVersion() > 1`. Campaign saves from this tree cannot be loaded by the same binary. The new format starts clean (see §7.5).

---

## 6. Target architecture

### 6.1 Ada package map

```
Megacorp                  -- name, version
Megacorp.Parameters       -- generator parameters and the re-roll rule
Megacorp.Types            -- coordinates, IDs, endian, errors
Megacorp.RNG              -- deterministic PRNG; child streams from a parent seed
Megacorp.Host             -- clock, log; storage hooks when the browser exists
Megacorp.Assets           -- abstract tileset, sprites, palettes, sounds
Megacorp.Assets.Placeholder
Megacorp.Data.Virtual_FS
Megacorp.World            -- regions, cities, corps, territory, economy
Megacorp.World.Gen        -- seeded world / region / city generation
Megacorp.Map              -- tile grid, walkability, surfaces
Megacorp.Map.Gen          -- city-block / mission-map generation
Megacorp.Path             -- pathfinding (ideas from pedpathfinding)
Megacorp.Peds
Megacorp.Actions          -- walk, follow, pickup, enter, shoot, hit, persuade…
Megacorp.Behaviour        -- police, panic, persuader/persuaded, civilian
Megacorp.Weapons          -- definitions + instances
Megacorp.Shots
Megacorp.Vehicles
Megacorp.Mission          -- tick, objectives, stats
Megacorp.Mission.Gen      -- populate a block: peds, vehicles, goals
Megacorp.Agents           -- player roster, mods, IPA
Megacorp.Research
Megacorp.Session          -- campaign clock, money, selected region
Megacorp.Save             -- versioned seed + snapshot + delta; migration
Megacorp.API              -- messages to/from the front end
```

There is no `Megacorp.Assets.Syndicate`. Original formats are not loaded.

This maps onto FreeSynd roughly as: `Map`/`Mission`/`leveldata` → `Megacorp.Map` + `Mission`; `ped*` + `ia/*` → `Peds`/`Actions`/`Behaviour`; `weapon*`/`shot` → `Weapons`/`Shots`; `vehicle`/`train` → `Vehicles`; `gamesession`/`gamecontroller`/`agent*` → `World`/`Session`/`Agents`; `research*`/`mod*` → `Research`; `system*`/`gfx`/`sound/sdlmixer*` → the browser (plus an optional framebuffer writer in Ada). `dernc` / `ccrc32` / original `file` open are not ported.

No Ada tasks or protected objects in the core (WASM runtimes still do not support them). No nested subprograms if the chosen WASM toolchain still forbids them; keep the style flat and portable. Contracts are part of the specs from item 1 (`-gnata`). SPARK is not used.

### 6.2 Core data model

**World.** A campaign has a 64-bit `World_Seed`, a generator version, and a list of regions. The region count is a generator parameter, default **40** (accepted range in 0.1.0: 1..512). Each region has: identity, geography hook on the world map, population and happiness, tax, owning corporation, intel/enhance levels, one or more cities, and links to neighbouring regions.

**Corporations.** A generator parameter, default **4** (accepted range in 0.1.0: 1..16): the player plus AI corps. Each has colour/logo, treasury, research progress, territory set, and relations. AI corps take turns between missions (`GameController::simulate_enemy_moves` is the precedent for the *idea*: seeded territory shifts, not a copy of that routine).

**City / mission map.** A mission is played on one or more **city blocks**: a 3D tile volume (tile x/y/z plus offsets). The block edge is a generator parameter, default **128×128** (each edge accepted in 0.1.0 from 1..1024). Tiles carry a tileset index and walk/shoot/solid flags. Buildings are first-class objects (footprint, height, corp owner, integrity) so destruction can be persisted without storing every tile if the building is intact. Roads, junctions, doors, and statics occupy the grid. The generator fills this structure. Nothing fills it from `MAPxx`/`GAMExx`.

**Peds, vehicles, weapons.** The same kinds of instances the reference uses: type (agent, civilian, police, guard, enemy agent), health, inventory, mods, IPA (adrenaline / intelligence / perception), action queue, behaviour components, group/persuasion. Vehicles include drivable cars and trains. Weapons are data-driven from an own table.

**Mission.** Objectives (assassinate, persuade, escape, … — from `objectivedesc`), spawn lists, mission stats, success/fail. Generated from a mission seed plus the current world snapshot (who owns the city, what the player equipped, which buildings already lie in ruins).

**Session.** Company name, money, campaign date, agent roster, research manager, selected region.

### 6.3 Simulation tick and determinism

- Host calls `Mission.Tick (Dt)` with a **fixed** `Dt` (33 ms to match FreeSynd’s animate threshold, unless tests show a shorter step is needed).
- The browser accumulates real time and issues zero or more ticks per animation frame (spiral-of-death cap).
- Tests call `Tick` N times with a recorded input stream.
- All “random” decisions take the mission or world RNG, not the clock.
- Hierarchical seeds: `World_Seed` → `Region_Seed` → `City_Seed` → `Block_Seed` / `Mission_Seed` via `Megacorp.RNG` child streams, so a change to one city does not reshuffle another, and a generator bugfix can bump a *local* gen version without discarding the whole world (see §7.6). The 0.2.0 implementation is xoshiro256\*\* seeded by SplitMix64; the reference vectors and the key formula are in the changelog.
- Replay identity: same `(World_Seed, gen version, snapshot, input log)` ⇒ same simulation state.

### 6.4 Ada core ↔ browser interface

The core does not know about DOM, Canvas, or WebSockets. `Megacorp.API` is a narrow message protocol (start as a simple tagged binary or CBOR; JSON is acceptable for early debugging). The WASM build uses it in-process (exported functions + shared memory). The server fallback serialises the same messages over a WebSocket.

**Browser → core:** `Create_World { seed | random, parameters, play mode }`, `Load_Save`, `Save`, `Menu_Command`, `Start_Mission { region, brief }`, `Input` (pointer in map space, keys, agent select, weapon, waypoints, IPA), `Pause`, `Step_Ticks { n }` (tests).

**Core → browser:** `Session_State`, `World_Map_State`, `Load_Progress`, `Frame` (see below), `Audio_Event { sample or track }`, `Mission_Status`, `Save_Completed`, errors.

**Frame payload (recommended):** Ada owns isometric order and animation frames and fills an **8-bit 640×400 framebuffer + 256-colour palette** in linear memory (the existing `Screen` model). JS copies it to an `ImageData` (or upscales with nearest neighbour). This is faithful and cheap in-process. A WebSocket fallback should not stream raw 256 KB × 30 fps; it would send a compressed display list or dirty rectangles instead. HUD can be either drawn into the same buffer (closest to FreeSynd) or overlaid in HTML later.

### 6.5 Data-file loading

- Virtual FS: named blobs (`"tileset.placeholder"`, and later our own asset names) from memory, OPFS, or a native path.
- Asset pack init: the placeholder pack. There is no Syndicate `DATA` import and no CRC of original files.
- Never assume a real filesystem in the browser.

### 6.6 Rendering, audio, input on the browser side

- Canvas 2D (or a WebGL nearest-neighbour upscale) for the 640×400 buffer.
- Input: pointer events mapped into game coordinates (menus 320×200, game 640×400), keyboard for the FreeSynd-like bindings (1–4 agents, F5–F12 inventory, etc.).
- WebAudio for one-shot samples and music. Own placeholder sounds. No original VOC/XMI and no FreeSynd Ogg tracks.

---

## 7. Procedural world and persistence

### 7.1 Design goals

- **Seeded and deterministic.** One master seed plus generator version fully define the *base* world.
- **Persistent.** Territory, ruins, corps, research, economy, and notable NPC/agent state survive closing the tab.
- **Playable without original maps.** Generation produces walkable, shootable city blocks with roads, buildings, peds, and objectives.
- **Modifiable later.** Generator improvements migrate, or re-roll only unvisited regions (see §7.6).

### 7.2 What is generated

From `World_Seed`:

1. **World map / regions** — layout, neighbours, biomes/density knobs, initial population and tax, starting owners among the corporations (player starts with a small footprint, as in Syndicate).
2. **Cities** — size, districts, which blocks exist, corp facilities, transport hooks (roads, optional rail).
3. **Mission maps (city blocks)** — tile volume: ground, roads, sidewalks, building footprints and heights, doors, signs, interior walkability where needed. This is the hard visual/playable piece; it must obey the tileset’s walk/solid contract so pathfinding and bullets stay honest.
4. **Population and props** — civilian density, police, guards, enemy agents, vehicles, pickups.
5. **Corporations** — names/colours (original or generated), starting research, relations.
6. **Missions** — objective type and targets derived from the political situation (assassinate a rival exec, persuade a scientist, escape a hostile block, destroy a facility already modelled as buildings).

The generator writes into the same `Map` / `Mission` types the sim ticks. There is no second “proc-gen format” at runtime.

### 7.3 What is persisted (mutable) vs regenerated

| Regenerated from seed + gen version (not stored, or stored only as a cache) | Stored in the save |
|---|---|
| Unmodified terrain and building footprints | `World_Seed`, generator version, format version |
| Default road layout | Campaign time, money, company identity |
| Stock furniture / decorative statics | Territory owners, tax, population, happiness |
| Generic ambient ped recipes (unless promoted to notable) | Research, agents, mods, inventory |
| | Building damage/destruction and tile patches in visited blocks |
| | Corp treasuries, relations, AI plans |
| | Notable NPCs (persuaded, recruited, named, dead) |
| | Mission outcomes and region “cleared / rebellious” flags |
| | Player-dropped items that should still be there |

Visited blocks that have been damaged store a **chunk patch** (destroyed buildings, changed tiles, lingering items). Unvisited blocks are not snapshotted; they are generated on first entry.

### 7.4 Save representation: seed + snapshot, with a short delta

Neither a pure replay log nor a only-seed save is enough (destruction and corp politics are heavy to replay from scratch every launch).

**Recommended hybrid:**

- Header: magic, format version, generator version, `World_Seed`, timestamp, friendly name.
- **Full snapshot** of mutable campaign state (the table above), plus patches for visited chunks.
- **Optional delta log** since the snapshot (commands / mission results) so a crash mid-mission can roll forward. Rotate into a new snapshot at mission end and at explicit save.
- Mission-in-progress: either “don’t save mid-firefight” (v1) or a full mission snapshot (agents, peds, projectiles) in v2.

Do not rely on FreeSynd `.fsg` compatibility (endian versions 1.0/1.1 and the 1.2 write bug). A new extension (e.g. `.mgc`) is fine.

### 7.5 Where it is stored

**WASM / static page (recommended route):** Origin-private storage on the player’s machine.

- Prefer **OPFS** (Origin Private File System) for binary snapshots (large enough for chunk patches, no third-party server, straightforward versioning of files).
- **IndexedDB** as fallback where OPFS is missing.
- The placeholder asset pack also goes in OPFS so a later visit does not re-fetch it. No copyrighted Syndicate data is stored.

**Native tests / GNAT 12.3:** ordinary files under a user directory.

**WebSocket-server fallback:** saves on the local machine next to the server process, not on a public host. A later hosted server would store only seed and snapshot.

### 7.6 Versioning and migration

- `Format_Version` (layout of the save file) and `Generator_Version` (algorithm that turns seeds into maps) are distinct.
- On load: if format is older, run a one-way migration (v1 → v2 → current). If format is newer, refuse and say so.
- Play mode decides whether a newer generator may touch an existing world. **Scenario:** the world is locked once generated. Generator updates do not re-roll it. **Free play and auto-play:** unvisited regions may be re-rolled; visited regions stay as left (patched snapshots, even if they would not match a re-roll). The rule lives in `Megacorp.Parameters` from item 1. Auto-play uses the same region rule as free play; what auto-play does besides that is a later item.
- Never silently re-seed a player’s world. A scenario world is never re-seeded. A free-play or auto-play world is never re-seeded as a whole; only an unvisited region may be generated again.

### 7.7 Effect on the port plan

Generation is not a cosmetic extra; it is how maps enter the sim. Pathfinding, AI, and combat are implemented against generated (and hand-built test) maps. There is no classic-map loader later.

---

## 8. Browser options and recommended route

Checked against public sources in November 2026.

**(a) Ada compiled to WebAssembly**, thin JS (or AdaWebPack Web bindings) for Canvas / WebAudio / file input.

As of mid-2026 this is real, not theoretical. GNAT-LLVM (ovenpasta gcc-16 branch, GCC 16.1 + LLVM 21) plus AdaWebPack provides `rts-wasm` (standalone) and `rts-wasm-emcc` (Emscripten, including SDL3 demos). Native WASM exception handling exists (`make wasm-eh` / `wasm-emcc-eh`). A HAC-in-the-browser demo (30 June 2026) ran HAC’s 133 tests fully in WASM. Limits that still matter: **no Ada tasks or protected objects**; some toolchains historically forbade nested subprograms; packaging is not yet a turnkey Alire install (work to add GNAT-LLVM/AdaWebPack to Alire was still a community proposal in 2026). File I/O is whatever we wrap around the JS/OPFS host.

**(b) Ada native server** (GNAT 12.3 + gprbuild) + browser client over WebSocket, Canvas rendering.

Fully usable today with Robert’s compiler. Excellent for the headless core and tests. Weaker as the *shipping* play path: the player must run a local server; a real-time isometric shooter is latency-sensitive; copyrighted art and the persistent world would have to be kept strictly local anyway.

**(c) Other.** GNAT-LLVM CCG (Ada → C → Emscripten) is a possible escape hatch if a direct WASM RTS blocks. Keeping C++ in the browser and writing only new Ada around it contradicts “all game logic in Ada.”

**Decided: (a), with (b) as fallback, and native GNAT 12.3 + gprbuild as the first host.** JavaScript stays a thin layer. Reasons: the game is real-time; the persistent world should stay in the browser origin (OPFS); one Ada core can be linked natively for tests and to WASM for play; procedural content and own art mean a public demo needs no copyrighted maps. Risks: toolchain build friction, RTS limits, fewer WASM debugging tools. Fallback is the same API over a local WebSocket, already designed in §6.4. Mitigation: no tasking in the core; a “hello framebuffer” spike early (item 20) before a playable mission depends on it.

SPARK is **not** used. Contracts and `-gnata` cover the checks we want now. RNC is out of scope with the original-data loaders.

---

## 9. Numbered implementation items

Each item is meant to be buildable and testable on its own. “Depends on” lists only earlier items. “Try” is what Robert can run when it lands. Sizes are rough, taken from the corresponding FreeSynd line counts plus new generator/save work. Old items 5 and 29 are gone; the list is 1–28.

### Phase A — Foundation (native Ada, no browser yet)

1. **Project skeleton.** GPR, `Megacorp.*` package shells, GPL headers, `Host` (log, clock), generator parameters and the play-mode re-roll rule, assertions (`-gnata`, `Pre` / `Post`, `Type_Invariant`), and a small smoke test. Depends on: nothing. Try: `gprbuild` and the smoke test on GNAT 12.3; the executable prints version 0.1.0 and the parameters. Size: small.
2. **Deterministic RNG with child streams.** Done in 0.2.0. xoshiro256\*\* seeded by SplitMix64; a child stream is a pure mix of the parent seed and a domain key (region, city, block, mission). Depends on: 1. Try: the smoke test checks the reference vectors, repeats a seed, and re-derives one region without moving another. Size: small.
3. **Core types and an in-memory map grid.** Done in 0.3.0. Terrain, height, walkable and drivable flags, bounds-checked access, and 4- and 8-neighbour lookup. The seeded test layout stands in until the city-block generator. Depends on: 1. Try: the smoke test, `bin/megacorp` for a text sample, and the browser page for seeds 1, 42, and 100. Size: small (FreeSynd `map.cpp`/`map.h` ~465 lines, plus a cleaner model).
4. **Virtual FS and asset interface.** Done in 0.4.0. Logical paths, a native disk backend, and an original isometric placeholder atlas. Depends on: 1. Try: the smoke test reads the index through the virtual file system, and the browser page draws seed 42 in isometric view. Size: small.

### Phase B — Headless simulation

5. **Walkability and pathfinding** on the in-memory map. Done in 0.5.0 for the grid, with separate walk and drive rules, 8-way steps that do not cut blocked corners, and a node budget. Depends on: 3, 2. Try: the smoke test, and the browser page's prepared paths for seeds 1, 42, and 100. Size: large (`pedpathfinding.cpp` 2,755 lines — expect a careful rewrite, not a dump). Vertical movement inside a single tile column is still later work; height is stored, and this search stays on the 2D grid.
6. **Peds and movement.** Done in 0.6.0 for one ped on a path: integer sub-tile steps, 8-way facing, speed, and the states standing, walking, and arrived. A fixed tick advances the route. Peds block each other; after a short wait the higher id repaths around occupied tiles, and the lower id keeps its route. Depends on: 5. Try: the smoke test (arrival tick, a two-ped meeting, identical traces) and the browser page's play, pause, and step controls. Size: medium (`ped.cpp` is 3,184 lines overall; this item is the movement slice).
7. **Action queue.** Done in 0.7.0. A ped has a fixed-capacity queue of walk, wait, turn, follow, and pick-up. One action runs per tick. Failure clears the queue and the ped stands. Orders replace the queue or append, and take effect on the next tick. Depends on: 6. Try: the smoke test, and the browser page's scripted mission for seeds 1, 42, and 100. Size: medium (`ia/action` + `pedactions` ~2,000+ lines). Vehicles and shooting stay later.
8. **Weapons, shots, damage, death.** Done in 0.8.0 for pistol, SMG, and rifle, ped health, a seeded hit/miss roll, and building line-of-sight. `Shoot_At` fires until the target is down, out of reach, blocked, or out of ammo. Depends on: 6, 2. Try: the smoke test, and the browser page's firefight for seeds 1, 42, and 100. Size: medium.
9. **Vehicles.** Drive on roads, enter/exit, collisions of the same kind as the reference. Depends on: 7. Try: ped enters a car and moves. Size: medium (`vehicle` 878 + train in the reference tree).
10. **Behaviour components.** Civilian panic, police wait-and-warn, persuader/persuaded. Depends on: 7, 8. Try: armed ped in sight of police produces a warning then fire after a documented delay (the reference uses 5 seconds; our delay is chosen when this item is written). Size: medium (`ia/behaviour` 412+ headers, plus ped hooks).
11. **Mission loop.** Start, fixed ticks, objectives, success/fail, stats. Headless runner: seed, inputs, N ticks, dump state. Depends on: 7–10. Try: a fixture mission (hand-built map) completes from a recorded input file. Size: medium-large (`mission.cpp` 3,197 in the reference tree).
12. **Comparison harness (optional but valuable).** Dump selected reference-tree state (positions, health, objective flags) vs Ada on a tiny hand-built fixture. Depends on: 11. Try: a diff report. Size: small tooling. Can lag if the C++ tree is hard to build.

### Phase C — Procedural generation

13. **City-block generator.** From a block seed and the city-map size parameter (default 128×128): ground, road grid, building footprints and heights, doors, walkable surfaces that pathfinding accepts. Depends on: 3, 2, 4, 5. Try: dump ASCII or PNG of several seeds; pathfinding still finds routes. Size: new work, medium-large.
14. **Block population and mission recipes.** Peds, vehicles, items, corp guards, a generated objective. Depends on: 13, 11. Try: `generate --seed=42 --mission` then auto-tick a smoke script (e.g. walk toward the target). Size: medium.
15. **World and city generator.** Regions (default about 40), neighbours, cities, initial territory, population/tax baselines, corporations (default 4). Depends on: 2, 13. Try: print a world map and corp owners for seed 42; regenerate and match. Size: medium.
16. **Corporation AI hook.** Between missions, seeded territory/research pressure (the idea of `simulate_enemy_moves`, not a port of that routine). Depends on: 15. Try: after a simulated “week”, ownership changes are stable for that seed. Size: small-medium.

### Phase D — Persistence

17. **Save format v1.** Header, seeds, generator version, play mode, snapshot of §7.3, visited chunk patches. Round-trip tests. Depends on: 15, 11. Try: mutate tax and destroy a building, save, load, observe the same world. Size: medium (the reference `gamesession` save is ~621 lines; this is a new format plus patch lists).
18. **Delta log + mission-end snapshot.** Recover a crash after a completed mission; mid-mission policy stays the open question in §10 (recommendation: discard an in-progress fight in v1). Depends on: 17. Try: kill the process after a mission-end write; reload is consistent. Size: small-medium.
19. **Migration hooks.** Fake a v0 save and upgrade it; refuse a future version cleanly. Honour the play-mode re-roll rule from §7.6. Depends on: 17. Try: a fixture old save loads with a “migrated” note. Size: small.

### Phase E — Browser front end, first playable mission

20. **WASM toolchain spike.** GNAT-LLVM + AdaWebPack: Ada fills a 640×400 8-bit buffer; the page blits it. If this fails in a bounded time, switch the remaining front-end items to the WebSocket fallback without changing the Ada API. Depends on: 1. Try: a moving placeholder sprite in the browser. Size: spike (toolchain, not game logic).
21. **Browser storage.** OPFS (IndexedDB fallback) for saves and the placeholder pack. No original-data file picker. Depends on: 4, 17, 20. Try: create a world, reload the page, the world is still there. Size: medium (JS + Host bindings).
22. **Input and tick in the page.** Pointer/keyboard → API; fixed-step ticks; framebuffer (or display list) each frame. Depends on: 20, 11. Try: walk a ped around a generated block with the keyboard. Size: medium.
23. **Playable first mission.** A generated block, at least one complete-able objective, shooting and movement, success/fail screen, then a save. Depends on: 14, 22, 17. Try: generate seed 42, finish the mission in the browser, reload, see the outcome and any destruction persist. Size: integration; this is the first “it feels like a game” milestone. Rough logic already built in B–D; UI glue is the added work.

### Phase F — Campaign layer and audio

24. **World-map UI.** Select region, see owners, tax/happiness, launch a mission, return after debrief with persisted territory. Depends on: 15, 16, 23. Try: play two missions in different regions; both results stay saved. Size: medium (FreeSynd `mapmenu.cpp` 463 is the reference for the screen’s job; the art is ours).
25. **Agents, equipment, research, economy.** Roster, mods, weapon shop, research tree, money. Depends on: 17, 24. Try: start research, skip campaign time (or play a mission), see it complete; agents keep mods after reload. Size: medium (`research*` + `agent*` + select menu are ~2,000+ lines in the reference tree).
26. **Menus and briefing.** Title, new/load world, debrief stats. No intro FLI. Depends on: 24. Try: a complete session without command-line flags. Size: medium (`menus/` is 10,852 lines in C++, much of it layout we can simplify).
27. **Sound and music.** WebAudio and own placeholder SFX, plus a music toggle. Depends on: 22. Try: shots and a music toggle. Size: small-medium.
28. **Variety and polish.** More block grammars, IPA meters, scanner, remaining weapons, destruction that stays visible on later visits, performance pass. Depends on: 23–27. Try: a short campaign of several generated missions that still looks consistent after reload. Size: ongoing.

---

## 10. Decisions and remaining questions

Closed on 2026-11-10 (see the changelog):

1. **Base tree.** The agreed design uses `freesynd/branches/rework-actions` as the logic reference. Not overridden.
2. **Front-end route.** Native GNAT 12.3 first, then WebAssembly, WebSocket server as fallback. JavaScript only for canvas, audio, input, and storage.
3. **Original data.** Not used. No CRC/RNC loaders, no classic maps.
4. **Art policy.** Own placeholder art.
5. **SPARK.** No. Contracts and `-gnata` from item 1.
6. **World scale.** Parameters: default 4 corporations, about 40 regions, city maps about 128×128.
7. **Tone and IP.** Distinct Megacorp setting, own names and art.
8. **Generator lock.** Scenario worlds are locked once generated. Free play and auto-play may re-roll unvisited regions; visited regions stay as left.

Still open:

1. **Mid-mission saves.** Recommendation: skip in v1 (discard an in-progress fight). Not required by the 2026-11-10 decisions.
2. **Scope cuts.** Recommendation: editor (`dump` / `src/editor`), multiplayer leftovers, and intro FLI stay out of scope. Not explicitly confirmed.
3. **Languages.** Classic EN/FR/IT/DE mission text left with the dropped classic mode. A string table for generated missions is still to be designed.
4. **Licence tag.** Closed in 0.8.0: MIT for the code and art we wrote, copyright Robert Boettcher. The imported GPL trees were removed in that same revision. “Own IP” in the earlier decisions means the setting and the art.

---

## 11. References

- Repo: https://github.com/RobertBoettcherSF/ADA-Megacorp-Simulator
- FreeSynd project (data warning): https://freesynd.sourceforge.io/dl.php.html
- libsyndicate (format notes): http://paul.chavent.free.fr/libsyndicate/libsyndicate.html
- AdaWebPack (WASM RTS + Web bindings): https://github.com/ovenpasta/adawebpack
- HAC in the browser via GNAT-LLVM (30 June 2026): https://forum.ada-lang.io/t/hac-running-in-the-browser-via-gnat-llvm-webassembly/4536
- GNAT-LLVM / WASM discussion: https://forum.ada-lang.io/t/gnat-llvm-in-alire-and-improved-wasm-support/4269

Line counts and file lists were measured on `master` at `fa08136`. This file is `docs/DESIGN.md`. The Ada skeleton for item 1 is `megacorp/`.
