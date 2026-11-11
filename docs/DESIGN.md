# Megacorp Simulator: FreeSynd analysis and Ada/browser porting plan

## Changelog

### 2026-11-11 — version 0.25.0, item 25

The player has a roster of named agents, a five-node research tree, and a purse that is separate from campaign cash. A day adds the item 24 income of owned regions and subtracts agent upkeep and the research grant. The purse is an integer, so it can go negative; hiring and shopping then stop. Weapons, augments, and armour have prices and open when the corporation research total reaches them. A lost mission kills one squad agent, and that death stays in the save. Format version 3 stores the roster, the unlocks, and the purse. A v1 or v2 file migrates forward. The page shows Finances, Research, and Roster. Ada computes the figures. JavaScript only draws them.

### 2026-11-11 — version 0.24.0, item 24

The world map is the strategic screen. Regions are drawn in the owner's colour. The player's regions are marked, and visited regions are drawn differently from unvisited ones. A hover or a tap opens a panel of owner, population, unrest, influence, income, the AI attack score, and the mission recipe. A corporations list shows region counts and strength. Pause, 1x, 2x, and 4x advance the campaign. Border fights and mission results from the delta log scroll in a ticker. On a narrow screen the panel is a bottom sheet. Ada computes every figure. JavaScript only draws.

### 2026-11-11 — version 0.23.0, item 23

Clicking a region on the world map starts that city's recipe in the live tick. The squad is up to four agents. The objective is the recipe's zone: reach it, escort to it, or sabotage the marked building. An enemy and a police officer are on the map and use the behaviour from item 10. Tap an enemy to attack. Reaching the zone wins. Standing still until the cap, or losing the squad, loses. The result is a mission line and a region line in the delta log. A win gives the region to the player and lowers unrest. A loss raises unrest. The region is marked visited either way.

### 2026-11-11 — version 0.22.0, item 22

The page ticks a generated 128 by 128 city inside the wasm module. `requestAnimationFrame` accumulates time and calls `megacorp_play` with a whole number of 33 ms steps, so the simulation does not depend on the frame rate. Pause, 1x, 2x, and 4x scale that accumulator. Pointer and key events are five integers. Ada selects a person, orders a walk, pans, and zooms. A touch drag pans and a pinch zooms. The city is drawn beside the world map, with the people and the cars moving. Each command and each batch of ticks is a line in the delta log. Replaying that log reproduces the city digest.

### 2026-11-10 — version 0.21.0, item 21

The browser file backend is `Virtual_FS.Browser`. The wasm module writes the version-2 snapshot `slot.mgc` and the delta log `slot.log` through it, and reads them back on `megacorp_boot`. A reload continues that day. New world calls `megacorp_reset` and replaces both files. The page stores the bytes in the Origin Private File System. If that directory cannot be opened, it uses IndexedDB. The two save files are also mirrored in localStorage, because a synchronous OPFS access handle is only available on a worker and the module runs on the main thread. A chosen tileset or sprite is copied into the module and stored at `assets/<name>` only when `Megacorp.Assets.Import` accepts it: a PNG signature, or JSON that names `tile_width` and `tiles`.

### 2026-11-10 — version 0.20.0, item 20

The browser runs the Ada world, not only a precomputed export. `web/megacorp.wasm` is built by AdaWebPack 22.1.0's llvm-gnat for `wasm32-unknown-unknown` and linked with `wasm-ld`. JavaScript loads that file, calls `adainit`, `megacorp_init(42)`, and `megacorp_step`, and reads a shared buffer for the map. The header shows `engine: wasm` and the version. The day counter advances on its own. Seed 42 at day 0 and day 10 matches `bin/megacorp --engine-check` and the smoke test. If the module fails to load, the precomputed traces stay. `megacorp/wasm/build.sh` rebuilds the file and downloads the compiler if it is missing.

The linked runtime is AdaWebPack's `libgnat.a`: GPL-3.0 with the GCC Runtime Library Exception 3.1. That exception allows the combined module to be distributed under MIT. The compiler and the runtime sources are not in this repository. The Text_IO stub, `To_Upper`, and the two C helpers are ours and are MIT.

### 2026-11-10 — version 0.19.0, item 19

`Megacorp.Save.Migrate` walks a format one version at a time. Each step is a pure function of the file text, with a precondition on the version it accepts and a postcondition that the result is the next version and its checksum matches. Version 2 adds a research total on each corporation, default 0, and a numeric generator algorithm. A version 1 file gains `algorithm 1` and a zero research field, then a new checksum. The loader logs `migrated save from version 1 to 2`. A version above 2 is refused with `wrong format version` before the checksum is considered.

The `generator` line stays the program version that first wrote the file. The algorithm stamp is separate. Algorithm 1 is the world from 0.15.0. Algorithm 2 changes only the city-seed key, so the stamp can be told apart. New games stay on algorithm 1. Loading rebuilds the base world with the stamped algorithm. It does not re-roll unvisited regions. A log sealed to the version 1 bytes still replays. Golden copies of a seed-42 snapshot and its four-day log are in `megacorp/tests/`.

### 2026-11-10 — version 0.18.0, item 18

`Megacorp.Save.Log` appends one checksummed line for each change since a snapshot. The file starts with `MGCD`, the format version, and the checksum of the snapshot it belongs to. A day line is `day none`, or `day tax` with the region and the rate. The other lines are a region row, a finished mission, a tile patch, a squad agent, or a re-rolled city seed. Loading is that snapshot plus a replay. After 32 lines, or when asked, the log is folded into a new snapshot. A torn final line is dropped and a warning is logged. A bad line earlier in the file is rejected.

`bin/megacorp --campaign 42 --days 0 --save slot.mgc --log slot.log` writes the baseline. `--load slot.mgc --log slot.log --days N` appends N days. `--compact` folds them. A scenario refuses a re-roll. Free play and auto-play re-roll only a region that has not been visited. A plain day-4 snapshot is 1062 bytes. An empty log is 46 bytes.

### 2026-11-10 — version 0.17.0, item 17

`Megacorp.Save` writes format version 1 through `Data.Virtual_FS`. The file starts with `MGC1`, the format version, and an FNV-1a checksum of the body. The body stores the master seed, the world day, the play mode, the locked flag, and the generator version. Corporations keep cash, earned, spent, and whether they are eliminated. Regions keep owner, tax, unrest, defence, tech, and a visited flag. A city is not stored: only tiles that differ from the generated city, as a patch list. The player squad is four agents, each with health, ammo, and a region. Names, colours, roads, population, and an untouched city are rebuilt from the seed.

`bin/megacorp --campaign 42 --days N --save FILE` writes that snapshot. `--load FILE` restores it and then plays N further days. A bad checksum and a format version other than 1 are rejected with those words. Migration of an older file waits for item 19. A 40-region save after 30 days is 1082 bytes. One ruined tile adds one patch line. The budget is 8192 bytes.

### 2026-11-10 — version 0.16.0, item 16

`Megacorp.World.Campaign` runs one strategic day. Each non-player corporation collects tax, moves the rate toward a trait target, buys defence on a threatened region, and may spend cash on one neighbouring region. Unrest at 100 hands the region to a neighbour. A corporation with no regions is eliminated and skips later days. `bin/megacorp --campaign SEED --days N` prints the ownership line for each day. The page steps through `campaign.json`.

The border fight is not a city mission. A year of days, twenty times over, cannot tick a generated city for every attack. Power is the cash spent, a trait bonus, and the tech of the attacking border. Hold is the region's defence, its tech, and a flat 40. Higher power takes the region. Seeds 1 through 20, after 365 days, give the most regions to Aggressive 8 times, Secretive 7, Mercantile 4, and Scientific 1. The player corporation does not take these turns, and in all 20 of those years it was eliminated.

### 2026-11-10 — version 0.15.0, item 15

Ped ids now run to 256 and vehicle ids to 64. The tick walks the people who are actually present, in id order, so the cap does not multiply the cost. A default city holds about 55 people: civilians in the residential blocks, the slums, the industrial strip, and the corporate core, guards at corporate doors, four police beats, and a squad of one to four agents. Eight vehicles are on the roads. Seeds 1 through 50 still all win. The split is 19 briefings, 18 snatches, and 13 contracts, and each of those wins.

`Megacorp.World.Gen` builds the campaign from the World and Region streams. Forty regions get generated names, population, tech, tax, unrest, a grid position, and a city seed. The roads of the grid keep the map connected, with a few extra links. Four corporations get generated names, distinct colours, distinct home regions, cash, and a trait. The first corporation keeps only its home. The others divide the remaining regions by which home is nearest. `bin/megacorp --world` prints it. The page draws the ownership map and opens a region's city.

### 2026-11-10 — version 0.14.0, item 14

`Megacorp.Mission.Gen` fills a generated city and gives it a mission recipe. The Block stream picks the stage. The Mission stream picks the recipe. Civilians, corporate guards, a police pair, parked cars, one car that drives, a case, and a cache come from that placement. The recipe is the objective set, the tiles those objectives use, an opposition level, and a tick cap. `bin/megacorp --mission SEED` runs it. Seeds 1, 42, and 100 export a Generated trace beside the older demos. The street fixture stays for the checks that name it.

### 2026-11-10 — version 0.13.0, item 13

`Megacorp.Map.Gen` builds a 128×128 city from the city-1 child of the world seed. The road grid includes the border and interior lines with gaps of 7 to 13 tiles, so the blocks are not one size. Four districts share the map: a corporate core, a residential field, an industrial strip, and a slum strip on the opposite side. Building height follows the district of that tile. Some blocks stay open as parks. A river crosses the city and the roads that meet it are bridges. One lake sits off the roads. Sidewalks are the open cells beside a road, and a built block keeps one pavement niche on its south face.

`bin/megacorp`, `bin/megacorp --export`, and `bin/megacorp --mission` use this city. `Test_Layout` stays for the unit checks that name it. Seeds 1, 42, and 100 are exported from the generator. There is no 0.12.0: item 12 was skipped, and the version stays equal to the item number.

### 2026-11-10 — version 0.11.0, item 11

`Megacorp.Mission` runs one mission. It is given the map, the cast, the vehicles, the items, the objectives, and a script of timed orders. It ticks until every objective is met, the squad is dead, or the tick cap is reached. The objectives are eliminate a ped, acquire an item, persuade a civilian, and evacuate onto a tile. A lost squad is checked before a win, so a mission cannot be won with nobody left. `bin/megacorp --mission SEED [--ticks N]` prints the result. The page gains a Mission trace: persuade, pick up the case, shoot the guard, and the firing tile is the evacuation zone.

Item 12, the C++ comparison harness, is skipped. That was the standing rule for this night.

### 2026-11-10 — version 0.10.0, item 10

`Megacorp.Behaviour` is a mood on each ped, stepped after the action queue. Civilians wander, then flee from a shot inside 8 tiles. Panic spreads 4 tiles to another civilian. Guards walk a patrol and shoot a hostile they can see. Police who can see an armed hostile warn for 12 ticks, then fire. Police who only hear a shot walk toward it. An agent standing next to a calm civilian persuades them after 8 ticks; the civilian then follows and does not flee. Each ped draws from its own child of the scene seed.

`bin/megacorp --export` adds that trace to seeds 1, 42, and 100. The page colours the marker by role and prints the mood. It does not decide.

### 2026-11-10 — version 0.9.0, item 9

`Megacorp.Vehicles` is a car and a van. A car has health 80, speed 2, and two seats. A van has health 120, speed 1, and four seats. Speed is sub-tile steps per tick, the same eight steps per tile a ped uses. The vehicle stores a tile, a facing, that step count, and health. It drives with `Megacorp.Path` in Drive mode, so every step is a road tile.

`Enter_Vehicle`, `Exit_Vehicle`, and `Drive_To` are queue actions. A ped boards from a neighbouring tile. Passengers copy the vehicle's tile, step, and facing. An intact vehicle blocks its tile, and the next tile once a crossing has started. `Shoot_Vehicle` uses the same aim, rate, hit roll, and building line of sight as `Shoot_At`. At zero health the vehicle stops and its passengers are ejected.

`bin/megacorp --export` adds that trace to seeds 1, 42, and 100. One ped walks to a car, drives along the roads, and gets out. Another ped shoots a van that already has a passenger. The page draws the car and the van in both views. It does not drive.

The placeholder atlas is now written by `tools/gen_tileset` (Ada). `tools/gen_tileset.py` is gone. On this machine the PNG bytes and `tiles.json` match the previous file.

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

The placeholder tileset is original art (flat-shaded isometric diamonds and building stacks, one sprite per terrain and height). Version 0.4.0 drew it with `tools/gen_tileset.py`. Version 0.9.0 writes the same pictures with the Ada tool `tools/gen_tileset` and removes the Python script. It is stored as `web/assets/atlas.png` plus `web/assets/tiles.json`, with `web/assets/LICENCE.txt`. `Megacorp.Assets.Placeholder` loads that index through the virtual file system. Tile id is `Terrain'Pos * 16 + height`. Map export writes that id in each cell. The browser draws the id from the atlas; it does not choose the sprite itself. The page toggles between the flat view and an isometric view (back to front, buildings stacked in the sprite). Hover in the isometric view uses the atlas alpha so a tall building is the tile under the cursor.

### 2026-11-10 — version 0.3.0, item 3

`Megacorp.Map` holds one city. The size comes from `Megacorp.Parameters` (default 128×128, each edge at most 1024). A tile has a terrain (`open`, `road`, `pavement`, `building`, `water`), a height 0..15, and stored walkable and drivable flags. Accessors are bounds-checked. Four- and eight-neighbour steps are there for pathfinding later (X east, Y south, origin 1).

`Test_Layout` is not the city-block generator. It is a seeded stand-in: open ground, a wandering river, a road grid (roads replace water, so the crossing reads as a bridge), pavement beside roads, and building blocks whose height comes from the city-1 child of the world seed. The same seed rebuilds the same map. The headless executable prints a northwest sample and a window on the river for seed 42.

The browser page does not run Ada. GNAT-LLVM/AdaWebPack is not set up on this machine, so the executable writes JSON (`--export DIR`) and `web/` only draws it. `./build.sh` regenerates `web/data/`. The page is [web/index.html](../web/index.html), and once this is on `master` it is at `https://raw.githack.com/RobertBoettcherSF/Megacorp-Simulator/master/web/index.html`.

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

### Runtime licence — libgnat is not a GPL project

`web/megacorp.wasm` is linked with `libgnat.a` from AdaWebPack 22.1.0. That archive is the GNAT runtime: **GPL-3.0 with the GCC Runtime Library Exception 3.1**. The same note is in the root `NOTICE` file.

This does not make Megacorp Simulator a GPL program. The exception is an extra permission on top of GPL-3.0. It applies when the runtime is combined with independent modules by an eligible compilation process. GNAT is that process. The exception then says the combined target code may be conveyed under terms of our choice. Those terms are MIT, which is the licence of every source file we wrote. We do not commit the runtime sources or the compiler. Rebuilding the module downloads them. The MIT sources do not have to be relicensed, and a person who receives the wasm file is not required to apply the GPL to the rest of the repository.

What would have made the project GPL is linking a runtime that had no runtime exception, or copying GPL source into the tree. Neither of those happened.

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

### Migration to Megacorp-Simulator

This repository is `RobertBoettcherSF/Megacorp-Simulator`. It was created on 2026-11-10 as one commit at version 0.8.0, moved off `ADA-Megacorp-Simulator`. That history does not contain the FreeSynd trees. URLs in this document, the root README, and `megacorp/README.md` use the new name.

### Item 9 — vehicles and the tileset tool

**Tileset tool.** `tools/gen_tileset.py` is replaced by `tools/src/gen_tileset.adb` and `tools/src/tile_art.adb`, built with `tools/tools.gpr` and the same warning switches as the simulation. It draws the same diamonds and writes `web/assets/atlas.png`, `tiles.json`, and `LICENCE.txt`. Keeping Python as a build step was the alternative. It was rejected because the language rule says Ada does this work. The PNG is deflated with the system zlib at level 9, the same call the Python generator used. On this machine (zlib 1.3) the PNG bytes and `tiles.json` are unchanged. An uncompressed PNG was the other way to stay deterministic without zlib. It would have made the file larger, so this build keeps the zlib path.

**Kinds.** Car: health 80, speed 2, two seats. Van: health 120, speed 1, four seats. These numbers are new. Speed is sub-tile steps per tick. A car crosses a tile in four ticks, twice a walking ped.

**Footprint.** One tile. During a crossing the vehicle also holds the next tile, the same rule as a ped. A longer hull was the alternative. It was left out because Drive is a point search, and a hull would need a new search.

**Who drives.** `Drive_To` is a ped action. It runs only while that ped is aboard that vehicle. The vehicle advances on those ticks. If two peds order the same vehicle on one tick, it advances once. There is no separate driver seat: any seated ped can give the order.

**Enter and exit.** `Enter_Vehicle` succeeds when the ped is on foot, within one tile (Chebyshev), the vehicle is intact, and a seat is free. The ped does not walk onto the vehicle tile, because that tile is blocked. `Exit_Vehicle` looks for a free walkable tile in the order north, east, south, west, then the diagonals, then a two-tile ring, and last the vehicle's own tile. A failed enter clears the queue, as the other actions do. Clearing a passenger's queue does not pull them out; `Exit_Vehicle` does that, and so does ejection.

**Passengers.** Each tick copies the vehicle's tile, sub-tile step, and facing onto each rider. A shot aimed at the vehicle does not also hurt the passengers. The alternative was to damage them too. It was left out so a wrecked van puts a living ped on the street, which the smoke test can see.

**Blocking and wrecks.** An intact vehicle blocks walking and driving. A wreck blocks driving and does not block walking, so people can leave the tile and a later ped can walk past. Vehicles yield to a ped on foot and to a lower vehicle id. After three waiting ticks the blocked vehicle repaths. That is the ped rule on the drive graph. A separate collision model was the alternative. It was left out so one occupancy rule covers peds and vehicles.

**Shots.** `Shoot_Vehicle` uses the same aim tick, rate, hit chance, and building line of sight as `Shoot_At`. At zero health the vehicle stops on its current tile and every passenger is ejected onto a free walkable tile. That ped's queue is cleared.

**Page.** Seeds 1, 42, and 100 gain a Vehicles trace. One ped walks to the car, enters, drives, and exits. A passenger who started in the car rides along. A second ped shoots a van; the van stops and its passenger steps out. The page draws a teal rectangle for the car and a longer amber one for the van. Grey is a wreck. A second rider is drawn a few pixels aside so both show; the trace stores one tile. The older views stay.

### Item 10 — behaviour

**Machine.** One mood per ped, updated after `Actions.Tick`. A new order replaces the queue and starts on the next tick, the same rule as a player order. The alternative was a second queue inside the behaviour package. It was left out so walk, shoot, turn, and follow stay the actions we already test.

**Roles.** Civilian, guard, police, hostile, agent. A hostile is the armed threat. Police do not warn guards or agents for carrying a gun. The alternative was "anyone with ammo". It was left out so a guard and an officer can stand in the same street.

**Radii.** Hearing 8 tiles, sight 6, panic spread 4. All Chebyshev. Sight is shorter than the pistol's reach of 8, so a guard does not fire at someone this machine cannot see. Hearing is wider than sight, so a shot carries past vision and a police officer who cannot see the shooter walks toward the noise. Panic does not check the wall; a civilian within 4 tiles of someone already fleeing flees too. The alternative was to require a clear line. It was left out so fear can turn a corner.

**Warning.** The reference waits about 5 seconds. This build waits 12 ticks. At a 33 ms tick that is under half a second, and on the page it is long enough to read "warn" before the shot. A 151-tick wait (5 seconds of 33 ms ticks) was the other choice. It would have made the exported trace mostly standing still.

**Flee and wander.** Flee steps straight away on the stronger axis, up to 5 tiles, then the ped calms if the noise is gone. Wander, every 8th tick while calm, picks an orthogonal walkable neighbour from that ped's child stream (`Mission` domain, key = ped id). A search of every farther tile was the alternative for flee. The straight step is enough to leave the shot and needs one path.

**Patrol and engage.** A guard walks the two ends of a short route, and that route repeats. If the two ends are the same tile, the guard stands there between fights. The fighting guard in the street demo is set up that way, so a finished shot does not send them to the corner of the map. A hostile in sight and in range replaces the patrol with `Shoot_At` until the hostile is gone. Hostiles shoot the nearest living person in sight and range. They do not chase, so a guard further down the same road keeps patrolling.

**Persuasion.** An agent next to a calm or wandering civilian for 8 ticks sets that civilian to persuaded. The civilian follows the agent and ignores gunfire. There is no chance roll. The alternative was a roll. It was left out so the smoke test can name the tick.

**Page.** Seeds 1, 42, and 100 gain a Behaviour trace on the first road column: two civilians flee a shot, one guard patrols, another guard shoots a second hostile, and a police officer warns then fires. Both bystanders are inside earshot; the smoke test is the one that places a civilian outside earshot and inside the spread radius. Gold is a civilian, orange a guard, blue police, red a hostile. The mood is printed in brackets. The older views stay.

### Item 11 — mission loop

**Who ticks.** `Play` is the mission. The caller passes the city, the cast, the fleet, the items, the objectives, and the script. `Play` is the only code that advances them. A record that heap-allocated a copy of the city was the alternative. It was left out because the city is already a large value and the tests already hold it.

**Objectives.** Four kinds, and every one of them has to be true. Eliminate: that ped is dead. Acquire: that item is no longer on the ground. Persuade: that ped's mood is persuaded. Evacuate: a living agent is standing on the zone tile. The squad is every ped whose role is agent. If none are alive, the result is lost, even on a tick when the objectives also became true. The alternative was to let the objectives win that tie. A mission with nobody left to extract is a loss.

**Script.** Timed orders in an Ada list, and the same list written as lines (`tick ped walk x y`, `wait`, `pick`, `shoot`, `turn`). `Load` reads that file back. The CLI does not take a file. `megacorp --mission SEED [--ticks N]` runs the built-in street mission. A lost or timed-out run is still a result, so the process exits 0. A bad argument exits 1.

**Fixture.** On the first road column, south of the behaviour scene: the agent waits beside a contact until persuasion lands, walks south for a case, shoots a guard who stays on one tile, and is already standing on the evacuation tile when the guard drops. The zone is that firing tile. A further walk south would have to pass the persuaded contact, who follows onto the only free road tile ahead. Scripted shots are the pistol. At one tile the hit chance is 100, so the seed does not change the winner. The default cap is 200 ticks. The fixture finishes at tick 83.

**Page.** Seeds 1, 42, and 100 gain a Mission trace. The line is the walk from the agent to the zone. Objective names sit beside the tick and flip from open to done. The case is drawn until it is picked up. The older views stay.

### Item 12 — comparison harness, skipped

Robert's standing rule for this night is to skip the C++ comparison. No harness, no shared fixture, no diff report. The Ada mission is checked by the smoke tests and the exported trace. The alternative was a small dump of positions against a built FreeSynd binary. It was not built.

### Item 13 — city-block generator

**Stream.** `Generate` draws on `RNG.Child (Make (Seed), City, 1)`, the same child `Test_Layout` used. The district frame is the first draws on that stream, so `District_At` can name a tile's district without storing a second grid. The alternative was a district id on the tile. It was left out because the JSON cell is five characters and the page already parses that.

**Districts.** Corporate is a square at a centre picked in the middle third of the map. On the default 128×128 map the half-extent is 21, so the core is 43×43 (1,849 tiles, 11 percent). Industrial is a strip on one side, thickness edge/5 (25 tiles, about 19 percent). Slums are the opposite side, thickness edge/6 (21 tiles, 16 percent). Everything else is residential (about 53 percent). Corporate wins where the core overlaps a strip. The alternative was a noise field. A strip is easier to see on the isometric view and the shares stay inside a fixed band. Smoke accepts corporate 8–16, industrial 12–25, slums 12–22, residential 45–65. Measured on seeds 1, 42, and 100 the shares were 11, 19, 16, and 52–53.

**Heights.** Corporate 9–14, residential 3–6, industrial 2–4, slums 1–3. Each building tile rolls inside the band of its own district, so a block that straddles a boundary changes height at the boundary. One roll for the whole block was the alternative. It would have put a slum-height tower in the core when the block centre sat just outside it.

**Roads.** The border is a ring road, and interior lines run the full width or height. The gap between lines is picked from 7 to 13, so block sizes vary, and a full span cannot leave a disconnected street. A maze of short segments was the alternative. It can fail to connect, and the demos need a long clear street.

**Water.** The river meanders with thickness 2 or 3, then the roads are painted over it, which is the bridge. The lake is a Manhattan disk of radius 3 to 5 and it does not paint a road tile. Painting the lake through the roads was the alternative. It would have cut the drive graph.

**Sidewalks and doors.** An open cell orthogonally next to a road becomes pavement. A block whose centre is residential becomes a park with chance 1/4; any other block, 1/10. A built block turns one south-facade cell into pavement when the cell south of it is already walkable, so the niche joins the sidewalk. A door on every face was the alternative. One niche is enough for a person to stand at the building, and the interior stays blocked.

**Reachable.** `Roads_Connected` is a 4-connected flood of every drivable tile. `Foot_Connected` is the same flood of every walkable tile. Every block sits between two of those full-span roads, and its sidewalk touches them, so a connected walkable set means every block can be walked to. Searching a path from every tile was the alternative. The flood answers the same question once.

**Demos.** Column 1 is part of the ring, so the behaviour street and the mission fixture keep the coordinates they already had. Both still finish on seeds 1, 42, and 100, and the fixture still wins at tick 83. Searching for a fresh vertical run was the fallback if that column had been a building. It was not needed.

**What stays on Test_Layout.** The 5×5 bounds check and the 24×24 layout equality checks still call `Test_Layout`. The export, the text sample, `--mission`, and the seeded demos call `Generate`.

### Item 14 — block population and mission recipes

**Streams.** Placement draws on `RNG.Child (Make (Seed), Block, 1)`. The recipe draws on `RNG.Child (Make (Seed), Mission, 1)`. Those are not the City stream the map already consumed, so generating the city and filling it do not move each other.

**Eight people.** `Peds.Ped_Id` is 1..8, and `Vehicles.Vehicle_Id` is 1..4, and `Actions.Item_Id` is 1..4. A crowd the size of the residential area does not fit. The cast is the agent, the contact, two guards, one more residential civilian, one slum civilian, and two police. Industrial civilians are zero. Corporate civilians are whoever of the contact happens to stand in the core, which the band allows as 0 or 1. The alternative was to raise the ped id cap. That would have changed the type every earlier package stores, so this item stays inside the cap.

**Where they stand.** The stage is the first road column of six tiles, in row-major order, whose south end has a walkable side tile touching a corporate building. The block stream picks one of the first 16 such columns. The agent stands one tile south of the contact. The case is two tiles further south. The stand, which is also the evacuation tile, is the south end. The target guard stands on that side tile, one step from the agent, so the pistol hit chance is 100. The second guard stands at another corporate door. The residential civilian and the cache are on residential ground away from the stage. The slum civilian's car drives seven tiles of slum road, also away from the stage. The two police beats are a horizontal run and a vertical run, neither of them through the stage. Two other cars are parked on roads.

**Why the extras do not block the squad.** The contact, the residential civilian, and the police are given a wait or a walk on their own beat. The guards patrol in place, and guards do not shoot an agent. The driver enters the car, drives, and gets out. Leaving them aboard after the drive made the next wander order drop them to standing while the seat still held them, and the following tick then failed the riding precondition. The exit is the fix.

**Recipes.** The mission stream picks one of three. Briefing is persuade and evacuate, opposition light, cap 100. Snatch is acquire, eliminate, and evacuate, opposition firm, cap 160. Contract is all four, opposition heavy, cap 200. Opposition here is which set and which cap, not a larger cast, because both guard posts are already filled. A roll for extra hostiles was the alternative. Hostiles shoot the agent, and a 50-seed sweep could not promise a win.

**Solved.** The auto-squad's script is queued at tick 1. Briefing waits beside the contact, then walks to the zone. Snatch walks to the case, picks it up, walks to the zone, and shoots the guard. Contract does the wait and then the snatch. Seeds 1 through 50 all win. On those seeds the split is 19 briefings, 18 snatches, and 13 contracts. Seed 42 is a briefing and wins at tick 44.

**Page.** Seeds 1, 42, and 100 gain a Generated trace: the eight people, the objectives, the two parked vehicles, and the car the slum civilian drives. The older Mission trace stays.

### Item 15 — world, and a denser street

**Caps.** `Peds.Ped_Id` is 1..256. `Vehicles.Vehicle_Id` is 1..64. The old loops walked every id in the type, which would have made a tick 32 times slower with an empty upper range. `Peds.Tick`, `Behaviour.React`, and the vehicle advance now sort the people or vehicles that are present and visit them in id order. That is the same order as the old scan. A sweep of seeds 1 through 50, each a full generated mission of about 55 people and 8 vehicles, took 9.7 seconds when each seed was a separate process, about 190 milliseconds a mission. In one process the smoke test is the same work without the process start. The alternative was a cap of 64 peds. 256 leaves room for a later crowd without another type change.

**Density.** Counts are a rate per 1024 tiles of that district, clamped. On the default 128×128 map that is about 12 to 28 residential civilians, 4 to 16 in the slums, 4 to 14 industrial civilians, and 1 to 10 corporate civilians, plus 3 to 10 guards, exactly 4 police, 6 parked vehicles, and 2 moving vehicles. The squad is a roll from 1 to 4. Allies stand off the road the leader uses and wait. Other civilians wait out the mission, because a hundred-tick wait is the longest single wait and a second wait covers the 200-tick cap. Letting them wander would let one of fifty people step onto the only road tile of the stage. Seeds 1 through 50 still all win: 19 of 19 briefings, 18 of 18 snatches, 13 of 13 contracts.

**World.** One World child stream places the corporations, the home shuffle, the colours, and the extra roads. Each region has its own Region child for its name, population (80 to 900, in thousands), tech (15 to 85), tax (5 to 35), unrest (0 to 55), and a small position jitter. The city seed is `Derive` of the world seed and that region's domain key, so naming the region does not move the city. Names are two or three syllables from a 24-syllable list, plus a corporation suffix (Combine, Works, Holdings, Foundry, Compact, Cartel). No real brand is used. Homes are a partial shuffle, so they differ. Corporation 1 keeps only its home. The other regions go to the nearest other home. Grid neighbours to the right and down make the graph connected; a one-in-four chance adds a diagonal. Colours are eight fixed inks shuffled, so four corporations never share a colour. Happiness from the design notes is not a separate field: unrest is the stored measure.

**Page.** `world.json` is seed 42. Each region also has `region-N.json`, the terrain only, so the page can open the city without the mission trace. The World map button draws a nearest-region colouring. A click prints the region's stats and loads that file.

### Item 16 — corporation day

**Who moves.** Corporation 1 is the player and does not choose tax, defence, or attacks. It still collects income, and its regions still gain unrest, so a high tax can lose the home. Corporations 2 and up act in id order. A corporation with no regions is marked eliminated at the start and end of the day and does not act. The alternative was to let the player corporation use its trait as well. Auto-play would then have no passive seat, and the smoke test would not show an elimination that the rule itself produces.

**Money.** Income for a region is population times tax, divided by 1000. Spending is defence, a scientific tech step of 150, and one attack. Nothing else creates or destroys cash. Each corporation stores the running earned and spent totals. The books are cash = opening cash + earned − spent.

**Tax and unrest.** Aggressive aims at tax 12, mercantile at 28, scientific at 16, secretive at 10. The rate moves by one point a day. Unrest above 70 cuts the rate instead. Unrest itself moves by tax/8 minus tech/25, clamped at 0 and 100. At 100 the region joins the neighbouring corporation with the most cash. If it has no foreign neighbour, unrest falls to 70 and tax is capped at 8. A region always has one owner.

**The fight.** Not `Mission.Play`. Attack prices are 600, 400, 350, and 250 for aggressive, mercantile, scientific, and secretive. Defence prices are 150, 250, 200, and 400. The trait bonus on an attack is 80, 20, 40, and 50. Power is the price plus the bonus plus a fifth of the attacker's border tech. Hold is the region's defence plus a fifth of its tech plus 40. Power above hold takes the region and leaves a quarter of the price as the new defence. Otherwise the defender keeps it and adds a fifth of the price to defence. Secretive corporations skip a target whose score is under 80. The score prefers unrest for an aggressive corp, population for a mercantile one, tech for a scientific one, and a low defence for a secretive one. One attack a day, the highest score, and the lowest region id breaks a tie. The turn is a pure function of the atlas, so a repeat does not need another random stream.

**A year.** Seeds 1 through 20, 365 days, all finish. The corporation with the most regions at the end is Aggressive in 8 seeds, Secretive in 7, Mercantile in 4, and Scientific in 1. The player seat is empty in all 20.

**Page.** `campaign.json` is seed 42 for 365 days. The day slider recolours the world map. The older city traces stay.

### Item 17 — save format version 1

**Text, not a private binary.** The snapshot is line-oriented text. A binary dump of the atlas would have stored names, roads, and whole cities, which the seed already defines, and a browser could not have inspected it. The alternative was a length-prefixed binary of only the mutable fields. Text is larger by a small factor and the checksum still catches a flipped byte. Measured size is 1082 bytes for the default world after 30 days, against a budget of 8192.

**What is stored.** Owner, tax, unrest, defence, and tech, because the day changes tech when a scientific corporation studies. Population is not stored: the day does not change it. Visited is stored, and it becomes true when a tile patch is recorded. The patch is one tile: region, coordinates, terrain, height, walk, drive. Applying it to a city rebuilt from that region's city seed is the ruined building. The squad is four agents at the player's home region, health 100, ammo 12, until a caller changes them. Company names, colours, homes, traits, region names, positions, and links are regenerated.

**Checksum and version.** Line 1 is `MGC1` and the format version. Line 2 is the FNV-1a 64 of every byte after that line. A version other than 1 is rejected before the checksum is considered, so item 19 can recognise an old file without treating it as corruption. A mismatched checksum says `checksum mismatch`. The file is written and read with `Virtual_FS.Write` and `Read`. The native backend creates the file under its root. A later OPFS backend implements the same call.

**Continue.** Load copies the mutable fields onto a world generated from the saved seed. Further days use the same day procedure as an uninterrupted run, so five days, a save, and five more days match ten days from the start. Patches and the squad do not feed the day formula, so they survive the round trip without changing the campaign.

### Item 18 — delta log

**A second file.** The snapshot stays the baseline from 0.17.0. The log is append-only so a crash can spoil only the last line. Rewriting one combined file would have put every earlier line at risk. `Virtual_FS.Append` creates the file or adds bytes. The native backend opens it in append mode. A later browser backend implements the same call.

**One checksum per line.** The snapshot checksum covers the whole body, which cannot survive a torn tail. Each log line ends with the FNV-1a 64 of the words before that checksum, using the same basis and prime as the snapshot. The header is `MGCD 1`. The next line names the snapshot the log belongs to. A format version other than 1 is rejected. Item 19 migrates snapshots, not this log.

**What a line records.** `day none` replays one campaign day, because that day is a pure function of the atlas. `day tax REGION RATE` sets that tax and then plays the day, so the input is in the log. A region line writes owner, tax, unrest, defence, tech, and the visited flag without playing a day. A mission line is the finished result (won, lost, or timeout) and marks the region visited. There is no value for a fight still in progress, so a crash during a fight leaves the last finished mission and drops the torn line. Tile patches and squad changes are their own lines. They are not produced by re-running the fight. A re-roll line stores the new city seed. Names, roads, and an untouched city stay derived.

**Re-roll.** Scenario play raises `scenario refuses re-roll`, including for a region nobody has visited. Free play and auto-play raise `visited region stays` once a patch or a mission has marked the region. The city seed and the patch are left as they were. A re-rolled seed is stored on the snapshot region because it is not the seed the generator builds. Finished missions are a `missions` section. Both are still format version 1. A 0.17.0 file has neither section and still loads.

**Torn tail.** If the file does not end on a newline, the partial tail is dropped. If the last complete line fails its checksum or does not parse, it is dropped too. The log warns `torn delta record dropped`. The kept lines are written back before the next append, so the new line is not glued onto the tear. A bad line earlier in the file raises `checksum mismatch`.

**Compact.** After 32 records, and when `--compact` is passed, the snapshot is written and the log is replaced by a header for that snapshot. The snapshot is written first. A crash before the log is replaced leaves a new snapshot and an old log. Replay compares the log's base with the snapshot and, on a mismatch, warns `delta base mismatch` and does not apply the log, so those days are not played twice. A plain day-4 snapshot is 1062 bytes. An empty log header is 46 bytes. The snapshot budget stays 8192.

**Command.** `--log FILE` replays that log and appends the new days. The snapshot file stays at the last compact until `--compact`. Without `--log`, `--save` still writes the world after N days. The snapshot and the log share a directory, because both calls go through one virtual-FS root.

### Item 19 — migration

**One step, on the text.** A decoded record would have hidden the checksum and the header. `Step` takes a whole file whose version is one behind current, checks that checksum, and returns the next version with a new checksum. `To_Current` calls `Step` until the file is current. Today that is a single call, version 1 to version 2. A third version will be another function, not a change to this one. A version the program does not know is refused with `wrong format version` before the checksum, so a future file is not reported as corruption.

**The version 2 field.** Each corporation stores research points. The default is 0, which is "research has not started". Item 25 can spend the field without another format bump for the first point. The squad was already in version 1, so it was not a new field. The migrated line is the old corporation line plus ` 0`.

**Generator stamp.** Format version and generator algorithm are different numbers. The version 1 `generator` line is the program version that wrote the file (`0.18.0` on the golden snapshot). Migration keeps that string and adds `algorithm 1`. Algorithm 1 is the city and world formula from 0.15.0. Algorithm 2 mixes a constant into the city-seed key and changes nothing else, so a test can see which stamp was used. New games stay on algorithm 1. Moving the default to 2 would reshuffle every city the mission tests and the page already publish. Loading calls `Generate` with the stamp, then copies the saved fields back. An algorithm number above 2 is `unknown generator version`.

**No silent re-roll.** A newer generator does not touch an old world at load, in any play mode. Re-rolling an unvisited region stays the explicit log record from item 18. Doing it automatically on migration would change a free-play map the player had not asked to change. Scenario and free play therefore take the same path here: rebuild with the stamp.

**The old log.** The log format is not migrated. Its base line is the checksum of the version 1 snapshot. After migration the snapshot's own checksum is different, so replay also accepts the checksum of the version 1 projection of the same fields. A log sealed to a different world is still skipped.

**Fixtures.** `megacorp/tests/v1-slot.mgc` is seed 42 at day 0, written by version 0.18.0. `v1-slot.log` is four `day none` lines sealed to that file. Loading them migrates the snapshot and replays to the same day-4 line as a continuous run.

### Item 20 — WebAssembly

**The path that worked.** GNAT 12.3 on this machine emits x86-64 only. AdaWebPack 22.1.0 (tag of 26 November 2022, about 53 MB) includes `llvm-gnat` with a WebAssembly backend. `llvm-gcc -mtriple=wasm32-unknown-unknown` compiles the world units. `wasm-ld` from LLVM 18 links them. A newer GNAT-LLVM tree was not built: the 22.1.0 compiler already emitted a working module, and building LLVM from source was not needed.

**Licence of the runtime.** The wasm `libgnat.a` in that release is the GNAT runtime: GPL-3.0 with the GCC Runtime Library Exception 3.1. The exception says a combination produced by GNAT may be conveyed under terms of our choice, so the module does not impose a GPL obligation on Megacorp. Our Ada, the two stub units, and `gnat_stub.c` are MIT. The compiler and the runtime sources are downloaded by `wasm/build.sh` and are not committed. `web/megacorp.wasm` is the combined module, which is what the static page needs.

**What the runtime could not do.** Its `system.ads` sets `No_Exception_Propagation`, so the two file writers could not keep an `others` handler. They already close the file before returning. The error path no longer closes a half-written file. `Ada.Text_IO` and `Ada.Characters.Handling` are not in that runtime. The build adds small MIT units for the calls the generator actually makes (`To_Upper`, and file operations the live entry never uses). `__gnat_put_exception` and `__gnat_grow` are the two C symbols the runtime imports and does not define. `__gnat_grow` is `memory.grow`.

**The page.** JavaScript only loads the module, calls `megacorp_init` and `megacorp_step`, and reads the buffer: day, corporations, regions, links. The canvas is still drawn in JS. The day counter moves by itself. Seed 42 day 0 digest is `cf28d9973a3bfe65` and day 10 is `d315dcd67089b6e9`, the same values as the native engine check. The city traces stay available from the City button. If the module does not load, the header stays `engine: trace` and the old exports draw the map.

**Not the WebSocket fallback.** The module runs. A local socket server was not added.

### Item 21 — browser storage and asset import

**Synchronous host, asynchronous origin storage.** The Ada backend is five imports: exists, length, read, write, append. OPFS can create a file and a writable stream on the main thread, but `createSyncAccessHandle` exists only inside a worker. The module cannot call it. The page therefore keeps the files in a map the imports see, fills that map before `megacorp_boot`, and writes `slot.mgc` and `slot.log` to `localStorage` before the import returns. The same bytes are queued to OPFS. If `navigator.storage.getDirectory` throws, the queue goes to IndexedDB. `?store=idb` forces that queue so the fallback can be checked. On the next load a snapshot already in localStorage is kept unless OPFS has one with a higher day. The log stays with the localStorage copy when that copy exists, because the snapshot day stays 0 until the log is compacted and a day number cannot say which log is newer.

**The same files as items 17–19.** Boot loads `slot.mgc`, rebuilds the atlas, and replays `slot.log`. A missing snapshot generates seed 42, captures auto-play, and writes both files. Advance commits `day none`, which is the campaign step, and compacts after 32 records. Reset overwrites both files with a new day-0 world. The page button is New world. The live timer calls advance, so a reload is not day 0. There is no new save format.

**What an import may be.** The page copies the chosen file into a 64 KB buffer and passes the name to `megacorp_commit_asset`. Ada accepts `.png` only when the first eight bytes are the PNG signature, and `.json` only when the text contains both `tile_width` and `tiles`. The stored name is `assets/` plus the basename, and that path has to be a logical path. Anything else returns 0. The page says Import refused and does not store the file. JavaScript does not decide the format.

### Item 22 — input and the city tick

**Fixed step.** One city tick is one call of `Play.Run`. The page adds frame time, times 1, 2, or 4, into an accumulator and spends it in steps of 33 ms. Pause adds nothing. A frame never asks for more than 8 ticks, so a stalled tab does not fast-forward a whole minute. The tick itself does not read the clock. Two runs with the same commands and the same tick count match, whatever the frame rate was.

**Commands are numbers.** JavaScript forwards a tap, a mouse drag, a touch drag, a pinch, or a key as a code and five integers. It does not decide what they mean. Code 1 selects the person on that tile, or, if the tile is empty and someone is selected, queues a walk. Code 2 replaces the selection with everyone inside the box. Code 5 pans by the drag. Code 4 pans and changes the zoom by one step. Arrow keys pan by two tiles. Minus and plus change the zoom. The walk starts on the next tick, which is the same rule the action queue already uses. Key repeat is dropped in the page so a held arrow is one command.

**The city.** `Map.Gen` builds the 128 by 128 map from the player's home city seed. Six people stand on pavement. Two cars drive between road tiles. The wasm compiler could not instantiate a vector inside `Map.Gen`'s connectivity search, so that search uses an array. The native result is the same breadth-first walk. The pathfinder no longer has an `others` handler: the wasm runtime rejects it, and the successful search already frees its nodes.

**The log.** `order` and `ticks` are delta-log lines. `Commit` applies them, so a replay is the same calls in the same order. The city digest mixes the tick, the camera, and every person and car. When the log is folded, the current city is written to `city.mgc` first, and the next load reads that file before replaying the lines that came after. A new world replaces both.

### Item 23 — the first playable mission

**The recipe, not a new mission.** `Mission.Gen.Build` still chooses briefing, snatch, or contract and the zone. The live cast is the squad from that recipe, plus one hostile and one police officer, not the whole generated crowd. The squad is dropped a few tiles from the zone so the walk is the objective rather than a hike across the city. The hostile is kept far enough away that a straight walk is not a firefight. Walking up to them and tapping is an attack. Their shots and the police reaction are `Behaviour.Step`, the same machine as item 10.

**Win and loss.** An agent standing on the zone wins. No agents left, or 48 ticks without the zone, loses. The page then shows the world map again. A win sets the owner to the player, adds defence, and clears unrest. A loss adds unrest and leaves the owner. Both set the visited flag through the existing mission and region log lines, so a later day does not re-roll that region in free play.

**One path for the replay.** The region click is logged as an order whose payload includes the city seed. Applying that order starts the mission, so the smoke test and a reload run the same calls. The scripted win is select the lead, order the zone, and tick. The scripted loss is tick without an order until the cap.

### Item 24 — world-map UI

**Ada computes, the page draws.** Income is population times tax, divided by 1000. Influence is defence plus tech, capped at 255. It is not unrest. AI pressure is the highest attack score among neighbouring corporations that can afford a strike, the same score item 16 uses, and zero when nobody can. The recipe preview is the same first draw `Mission.Gen.Build` makes from the city seed, so the name matches the mission without generating the city. Strength is the defence and tech of the regions a corporation holds. Visited comes from the snapshot.

**The log is the ticker.** A campaign day that changes an owner appends the existing region record. The headline is "Region N held by C" for a border fight, "Mission N won" or lost for a mission, and a tax line when the rate was an input. Day lines with no input are not news. The brief keeps those headlines even after the log is folded.

**The campaign clock.** Pause, 1x, 2x, and 4x spend accumulated frame time as strategic days, one second at 1x. They do not advance the campaign while a mission is in progress. The city tick still uses the same buttons inside a mission.

**The narrow screen.** Below 720px the side panel is a bottom sheet. Tapping a region opens it. The handle collapses it. The map width follows the page, so the iPhone view is the same data on a smaller canvas.

### Item 25 — agents, research, and the economy

**The purse is not campaign cash.** Corporation cash on the atlas is what the item 16 AI spends, and it stays in the world digest. The player's funds are a separate integer on the snapshot. Each campaign day adds the item 24 income of regions owned by corporation 1, then subtracts 30 for every living agent and the research grant. A grant is 0, 40, or 80 points, added to the v2 research total. Funds may go negative. While they are negative, or short of the 400 hire price, hiring is refused and the panel says so.

**The roster is generated.** A new game starts with two operatives. A hire appends the next person from the world seed and the roster index, so the name, health, accuracy, speed, and morale replay. Six is the limit. Two augment slots start empty. A weapon starts as a pistol. SMG, vest, reflex, rifle, and plate open from the research total, in that order, without spending the points. Buying one writes it onto the agent. The squad picker stores four roster indexes. A lost mission kills the living pick with the lowest health. A win pays 250 plus that region's income. The death, the gear, and the purse are in the snapshot.

**Format 3.** The new lines are funds, grant, the roster, the four picks, and the five unlock flags. A v2 file gains an empty roster and 1500 funds. A v1 file still walks through version 2 first. The legacy seal used by old logs does not include these lines, so a v1 log still replays. Hire, grant, gear, pick, and payoff are delta-log records. A campaign day is the same day record as before; applying it now also closes the books.

### 2026-11-10 — Robert's decisions (override anything later in this document that conflicts)

1. **Language and route.** All logic, and as much of the rest as possible, in plain Ada. JavaScript is only a thin browser layer (canvas, audio, input, storage). The Ada core is built natively first with GNAT 12.3 and gprbuild, and later compiled to WebAssembly (GNAT-LLVM / AdaWebPack). A WebSocket server is the fallback.
2. **Own setting and own IP.** Distinct Megacorp names and own placeholder art. No original Syndicate data, ever. Dropped old item 5 (CRC/RNC loaders for original data) and old item 29 (classic original maps). `Megacorp.Assets.Syndicate` is not part of the package map.
3. **Contracts, not SPARK.** `Pre` / `Post`, `Type_Invariant`, and `Assert`, compiled with `-gnata`, from the first commit. No SPARK for now.
4. **Scale is a generator parameter.** Default 4 megacorporations, about 40 world regions, city maps about 128×128 tiles. The 0.1.0 skeleton accepts corporations 1..16, regions 1..512, and a city-map edge 1..1024, with those defaults.
5. **Persistence.** Scenario worlds are locked once generated. In free play and auto-play, unvisited regions may be re-rolled; visited regions stay as left.

Items below are renumbered **1–28** after those two drops. "Own IP" here is the setting and the art (old question 7), not a choice of software licence. The licence tag (old question 12) is still open; the 0.1.0 skeleton uses GPL-2-or-later headers, matching FreeSynd's file headers and item 1, until that choice is closed.

**Status:** agreed design, updated 11 November 2026. Items 1–11 and 13–25 (version 0.25.0) are implemented under `megacorp/`. Item 12 is skipped, so there is no 0.12.0. The browser check page is `web/`. The code we wrote is MIT. The WebAssembly runtime linked into `web/megacorp.wasm` is GPL-3.0 with the GCC Runtime Library Exception 3.1. Why that does not make this project GPL is logged under "Runtime licence" above and in the root `NOTICE` file.  
**Date:** 10 November 2026, Europe/Berlin  
**Source repo:** https://github.com/RobertBoettcherSF/Megacorp-Simulator (branch `master`)  
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
9. **Vehicles.** Done in 0.9.0. A car and a van drive on roads, peds enter and exit, passengers move with the vehicle, the vehicle blocks its tiles, and shots destroy it and eject the passengers. Depends on: 7. Try: the smoke test, and the browser page's vehicle trace for seeds 1, 42, and 100. Size: medium.
10. **Behaviour components.** Done in 0.10.0. Civilians wander and flee, panic spreads by radius, guards patrol and engage, police warn for 12 ticks then fire, and an agent can persuade a neighbour. Depends on: 7, 8. Try: the smoke test, and the browser page's behaviour trace for seeds 1, 42, and 100. Size: medium.
11. **Mission loop.** Done in 0.11.0. A mission ticks the cast, vehicles, items, and objectives until win, squad loss, or timeout. `bin/megacorp --mission SEED [--ticks N]` prints the result. A script file round-trips. Depends on: 7–10. Try: the smoke test, `bin/megacorp --mission 42`, and the browser page's mission trace for seeds 1, 42, and 100. Size: medium.
12. **Comparison harness.** Skipped in 0.11.0. Robert's standing rule for this night was to leave the C++ comparison out. No harness and no diff report. Depends on: 11. Try: nothing to run. Size: not built.

### Phase C — Procedural generation

13. **City-block generator.** Done in 0.13.0. From the city seed and the city-map size (default 128×128): ground, a road grid with varied block sizes, districts, building heights, doors, parks, a river with bridges, and sidewalks that pathfinding accepts. `Test_Layout` remains for its unit checks. Depends on: 3, 2, 4, 5. Try: the smoke test, `bin/megacorp` for a text sample of seed 42, and the browser page for seeds 1, 42, and 100. Size: new work, medium-large.
14. **Block population and mission recipes.** Done in 0.14.0. From the Block and Mission streams: civilians, corporate guards, police beats, parked and moving vehicles, items, and a recipe of objectives, placement, opposition, and a tick cap. `bin/megacorp --mission SEED` plays it. Depends on: 13, 11. Try: the smoke test, `bin/megacorp --mission 42`, and the browser page's Generated trace for seeds 1, 42, and 100. Size: medium.
15. **World and city generator.** Done in 0.15.0. From the World and Region streams: about 40 named regions, adjacency, a city seed each, and 4 corporations with names, colours, homes, cash, and a trait. The ped cap is 256 and the vehicle cap is 64, with a denser street. Depends on: 2, 13. Try: `bin/megacorp --world 42`, the smoke test, and the browser page's World map. Size: medium.
16. **Corporation AI hook.** Done in 0.16.0. One day: non-player corporations tax, spend, attack, and suffer revolts. The fight is a formula. `bin/megacorp --campaign SEED --days N` prints the ownership line. Depends on: 15. Try: `bin/megacorp --campaign 42 --days 30`, the smoke test, and the day slider on the world map. Size: small-medium.

### Phase D — Persistence

17. **Save format v1.** Done in 0.17.0. Magic, format version, checksum, master seed, world day, play mode, locked flag, mutable region and corporation fields, tile patches, and the player squad. Written through the virtual file system. Depends on: 15, 11. Try: `bin/megacorp --campaign 42 --days 10 --save slot.mgc`, then `--load slot.mgc --days 10`. Size: medium.
18. **Delta log + mission-end snapshot.** Done in 0.18.0. Append-only checksummed lines since the snapshot: days and their inputs, region rows, finished missions, tile patches, squad changes, and re-rolls. A torn final line is dropped. Compact after 32 lines or on demand. A scenario refuses a re-roll. Depends on: 17. Try: `bin/megacorp --campaign 42 --days 0 --save slot.mgc --log slot.log`, then `--load slot.mgc --log slot.log --days 10`, then `--compact`. Size: small-medium.
19. **Migration hooks.** Done in 0.19.0. One pure step from format version 1 to 2. Version 2 adds research points, default 0, and a generator algorithm stamp. A newer format is refused. A version 1 log still replays. Depends on: 17. Try: `bin/megacorp --campaign 42 --days 0 --load megacorp/tests/v1-slot.mgc --log megacorp/tests/v1-slot.log`. The note is `migrated save from version 1 to 2`. Size: small.

### Phase E — Browser front end, first playable mission

20. **WASM toolchain spike.** Done in 0.20.0. AdaWebPack 22.1.0 llvm-gnat emits the world core as `web/megacorp.wasm`. The page calls `megacorp_init` and `megacorp_step` and draws the live map. Seed 42 matches the native engine check. Depends on: 1, 15, 16. Try: open `web/index.html`; the header says `engine: wasm` and the day counter moves. `node megacorp/wasm/check.mjs` compares the module with `bin/megacorp --engine-check`. Size: spike.
21. **Browser storage.** Done in 0.21.0. The wasm module reads and writes `slot.mgc` and `slot.log` through `Virtual_FS.Browser`. The page uses OPFS, IndexedDB when OPFS cannot be opened, and a localStorage mirror of the two save files. Reload continues the saved day. New world resets it. A chosen tileset or sprite is stored only after `Megacorp.Assets.Import` accepts it. Depends on: 4, 17, 20. Try: open `web/index.html`, let the day move, reload, and see the same day; New world starts again. Size: medium (JS + Host bindings).
22. **Input and tick in the page.** Done in 0.22.0. The wasm module ticks a 128 by 128 city. The page accumulates animation frames into fixed steps and offers Pause, 1x, 2x, and 4x. Pointer and key events are a command queue. Ada selects, orders a walk, and pans or zooms. Commands and tick batches are delta-log lines, and a replay matches the city digest. Depends on: 20, 11, 13. Try: open `web/index.html`, tap a person, tap a tile, and watch them walk. Speed changes how fast the sim counter moves. Size: medium.
23. **Playable first mission.** Done in 0.23.0. A region click starts that city's recipe with a squad of up to four agents. The objective is on screen. Reaching the zone wins. A timeout or a dead squad loses. The result changes ownership or unrest, marks the region visited, and is stored in the delta log. Depends on: 14, 22, 17, 10. Try: open `web/index.html`, click a region, tap an agent, tap the marked tile, and see the world map show the new owner. Size: integration.

### Phase F — Campaign layer and audio

24. **World-map UI.** Done in 0.24.0. The map is coloured by owner, the player's regions are marked, and visited regions are drawn differently. A hover or tap opens Ada's figures for that region: owner, population, unrest, influence, income, AI pressure, and the recipe preview. Corporations list region counts and strength. Pause, 1x, 2x, and 4x advance the campaign. Border fights and mission results from the delta log are the ticker. A narrow window uses a bottom sheet. Depends on: 15, 16, 23. Try: open `web/index.html`, hover a region, and read the panel. Let the day run and see a border fight in the log. Size: medium.
25. **Agents, equipment, research, economy.** Done in 0.25.0. The roster is named and generated. Hiring costs 400. A dead agent stays dead in the save. Weapons, augments, and armour have prices and unlock from the research total. Daily income, upkeep, and the research grant move an integer purse that can go into debt, which closes hiring. The squad picker feeds a mission's payoff. Format version 3 migrates from v2. The page has Finances, Research, and Roster panels. Depends on: 17, 24. Try: open `web/index.html`, hire an agent, set a research grant, and watch the funds change as the day moves. Size: medium.
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

- Repo: https://github.com/RobertBoettcherSF/Megacorp-Simulator
- FreeSynd project (data warning): https://freesynd.sourceforge.io/dl.php.html
- libsyndicate (format notes): http://paul.chavent.free.fr/libsyndicate/libsyndicate.html
- AdaWebPack (WASM RTS + Web bindings): https://github.com/ovenpasta/adawebpack
- HAC in the browser via GNAT-LLVM (30 June 2026): https://forum.ada-lang.io/t/hac-running-in-the-browser-via-gnat-llvm-webassembly/4536
- GNAT-LLVM / WASM discussion: https://forum.ada-lang.io/t/gnat-llvm-in-alire-and-improved-wasm-support/4269

Line counts and file lists were measured on `master` at `fa08136`. This file is `docs/DESIGN.md`. The Ada skeleton for item 1 is `megacorp/`.
