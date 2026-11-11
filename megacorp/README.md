# Megacorp Simulator 0.24.0

Headless Ada core for Megacorp Simulator. Version 0.24.0 is the
strategic world map (design item 24). Item 12, the C++ comparison,
stays skipped, so there is no 0.12.0.
Version 0.6.1 keeps the browser
page working when
WebKit refuses to read the atlas pixels. Later packages are still
specs.

A browser page draws maps the Ada program has already exported. It
does not run the simulation. After this branch is on `master`:

<https://raw.githack.com/RobertBoettcherSF/Megacorp-Simulator/master/web/index.html>

The design, including Robert's decisions of 10 November 2026, is
[`../docs/DESIGN.md`](../docs/DESIGN.md).

## Requirements

- GNAT 12.3 (`gnat` / `gcc-12` reporting `12.3`)
- gprbuild
- Linux x86_64, for the binary the script packages

The executable links against the GNAT 12 runtime (`libgnat-12` and
`libgnarl-12`). `Ada.Real_Time` pulls in the tasking runtime library.
The core creates no tasks and no protected objects.

On Ubuntu 24.04 the 12.3 compiler is the original noble package
`gnat-12=12.3.0-17ubuntu1` (the noble-updates package is 12.4). Pin
`gcc-12`, `cpp-12`, `libgcc-12-dev`, `gcc-12-base`, and `libgnat-12`
to `12.3.0-17ubuntu1` as well. gprbuild itself may be linked with a
newer runtime; it still drives GNAT 12.3 when that compiler is the
`gnat` on `PATH`.

## Build and run

From this directory:

```sh
./build.sh
```

That builds with `gprbuild -P megacorp.gpr -p`, regenerates the
tileset with the Ada tool `tools/gen_tileset`, runs `bin/megacorp`
and `bin/megacorp_smoke`, and rewrites `../web/data/` from the Ada
map export, including precomputed walk and drive paths, ped traces,
the vehicle demo, the behaviour demo, and the mission demo.
It also writes `dist/megacorp_v0.24.0.zip` for
local use; that archive is not a deliverable.

The same steps by hand:

```sh
gprbuild -P megacorp.gpr -p
./bin/megacorp
./bin/megacorp_smoke
```

`megacorp.gpr` builds the static library (`megacorp_lib.gpr`) and both
executables. `bin/megacorp` prints the version, the generator
parameters, and a text sample of seed 42. `bin/megacorp --export DIR`
writes `index.json`, one JSON map per fixed seed (1, 42, 100),
and `encounter.json` for the two-ped meeting.
`bin/megacorp_smoke` exits 0 when the smoke checks pass.

Assertions and contracts are compiled in. Warnings and GNAT style
checks are errors. The switch list is `switches.gpr`:

- `-gnat2012` Ada 2012
- `-gnata` assertions, preconditions, postconditions, type invariants
- `-gnato` overflow checks
- `-gnatwa` warnings
- `-gnatwe` warnings and style checks are errors
- `-gnaty` GNAT style
- `-g` debug information

## Package

Build products (`obj/`, `lib/`, `bin/`) are not committed. The
exported JSON under `web/data/` is committed so the page can be opened
without a local build.

## What 0.24.0 contains

Real code: version, generator parameters (defaults 4 corporations,
40 regions, 128 by 128 city maps), the play-mode re-roll rule, a
monotonic clock, a log, `Megacorp.RNG`, and `Megacorp.Map`.

The RNG is xoshiro256\*\* seeded by SplitMix64. Child streams come
from the parent seed and a key (world, region, city, block, mission).

The map is one city. Each tile stores terrain, height, and walkable
and drivable flags. `Megacorp.Map.Gen.Generate` fills that city from
the city-1 child of the given seed: a road grid with a border, blocks
of different sizes, four districts, parks, a river with bridges, and
one lake kept off the roads. Sidewalks are the walkable cells beside
a road, and one door niche opens the south face of a built block.
`Test_Layout` is still there. The older unit checks call it. The
export and the sample call `Generate`.

`Megacorp.Mission.Gen` fills that city from the Block and Mission
streams. A ped id runs to 256 and a vehicle id to 64. On the default
map the crowd is about 55 people: civilians in every district,
guards at corporate doors, four police beats, and a squad of up to
four agents. Eight vehicles are parked or driving. A recipe is one
of briefing, snatch, or contract. `bin/megacorp --mission SEED`
plays it. The street fixture is still what the older mission checks
call.

`Megacorp.World.Gen` builds the campaign from the World and Region
streams: 40 named regions, adjacency, a city seed each, and 4
corporations with names, colours, home regions, cash, and a trait.
The player corporation keeps only its home region. `bin/megacorp
--world` prints that world. The export writes `world.json` and one
terrain file per region.

`Megacorp.World.Campaign` advances that world one day at a time.
Each non-player corporation, following its trait, collects tax,
nudges the rate, buys defence, and may attack a neighbouring region.
Unrest can hand a region to a neighbour. A corporation with no
regions is out of the turn. The border fight is a formula of cash,
tech, and defence, not a full city mission. `bin/megacorp
--campaign SEED --days N` prints who owns how many regions after
each day. The export writes `campaign.json` so the page can step
through a year. `--save FILE` writes the world after those days,
and `--load FILE` continues from a snapshot. The file is format
version 1: magic, checksum, seed, day, play mode, and only the
fields play can change. Names and an untouched city are rebuilt.
`--log FILE` appends each later day, and `--compact` folds that
log back into the snapshot. A torn final line is dropped. A format
version 1 file migrates to version 2 on load. Version 2 adds a
research total per corporation, default 0. The generator algorithm
is stamped, and an old world is rebuilt with that stamp.
`wasm/build.sh` compiles that same world to `web/megacorp.wasm`.
The page loads it and draws the live map. `node wasm/check.mjs`
compares the module with `bin/megacorp --engine-check`. The module
also writes `slot.mgc` and `slot.log` through the browser file
backend. The page keeps those files in the Origin Private File
System, or in IndexedDB when that is unavailable, and mirrors them
in localStorage so a reload continues the same day. New world
replaces them. A chosen tileset or sprite is stored only when
`Megacorp.Assets.Import` accepts it. The page also shows that
city, 128 by 128, with people and cars moving. A fixed Ada tick
is driven from the animation frame. Pause, 1x, 2x, and 4x set
how many of those ticks run. A tap, a drag, a pinch, or an arrow
key is a command. Ada selects, orders the walk, and moves the
camera. The command is a line in the delta log. Clicking a region starts
that city's recipe: a squad of up to four agents and an objective
to reach a zone, escort to it, or sabotage the marked building.
An enemy guard and a police officer use the behaviour from item 10.
Tap an enemy to attack. Winning gives the region to the player and
lowers unrest. Losing raises unrest. Either way the region is
visited, so free play will not re-roll it. The world map is the
strategic screen. Ada exports income, influence, AI pressure, the
recipe preview, corporation strength, and the latest log headlines.
The page only draws them. Pause, 1x, 2x, and 4x advance the
campaign. A narrow window turns the side panel into a bottom sheet.

`Megacorp.Data.Virtual_FS` reads logical paths. The disk backend is
`Virtual_FS.Native`. `Megacorp.Assets.Placeholder` loads
`web/assets/tiles.json` through that interface and maps terrain plus
height to a tile id. The pictures are original, produced by
`tools/gen_tileset`. See `web/assets/LICENCE.txt`.

`Megacorp.Path` is A* with integer costs (10 orthogonal, 14 diagonal).
Walk uses the walkable flag. Drive uses the drivable flag. A diagonal
step is refused when it would cut a blocked corner. The result is a
tile list, `No_Path`, or `Budget_Exceeded`. Tie-breaking is fixed, so
the same query repeats the same path.

`Megacorp.Peds` advances a ped along a walk route by a fixed tick.
Position inside a tile is an integer number of sub-tile steps (8 per
tile). Facing is one of eight directions. Speed is steps per tick.
The state is standing, walking, or arrived. Peds occupy tiles. The
ped with the greater id waits, then repaths around occupied tiles;
the lower id keeps its route. The same inputs produce the same trace.

`Megacorp.Actions` queues walk, wait, turn, follow, and pick-up.
The queue holds at most 8 actions. Each tick runs the front action.
The next action starts on the following tick. A failure clears the
queue and the ped stands. An order replaces the queue or appends,
and takes effect on the next tick. `Walk_To` uses the ped movement,
including blocking and repathing. A case is an item on a tile.

`Megacorp.Weapons` lists a pistol, an SMG, and a rifle. Each has a
reach, a damage, a number of ticks between shots, and a magazine.
A ped has 100 health. `Megacorp.Shots` rolls a hit on a child of the
fight seed and blocks the shot on a building tile. `Shoot_At` aims,
then fires until the target is down, out of reach, blocked, or out
of rounds. A downed ped stops and that queue is cleared.

`Megacorp.Vehicles` is a car and a van. Each stores a tile, an
8-way facing, a sub-tile step, a speed, and health. Drive uses the
road flag. A ped queue can enter, drive, and exit. Passengers move
with the vehicle. An intact vehicle blocks its tile. A shot can
wreck it; the wreck stops and the passengers are ejected.

`Megacorp.Behaviour` sets a mood on each ped after the action
queue. Civilians wander, then flee from gunfire, and panic spreads
to a nearby civilian. Guards patrol and shoot a hostile in sight.
Police warn for 12 ticks, then fire. An agent can persuade a
neighbour; that civilian follows and does not flee. Each ped uses
its own child of the scene seed.

`web/index.html` draws the exported seeds. Flat view is one colour per
terrain. Isometric view uses the atlas and the exported tile id, back
to front, with building stacks. Each seed includes Ada-computed walk
and drive paths, plus a walk into the river that has no path, and a
per-tick trace for the walk. `encounter.json` is two peds meeting.
Play, pause, and step replay the trace and draw a marker with its
facing. Each seed also has a scripted mission: one ped walks, waits,
turns, follows a second ped, and picks up a case. The page shows the
current action and the remaining queue beside the tick counter, and
draws the case until it is picked up. Each seed also has a
firefight: shot lines, health bars, and ammo from the Ada trace.
Each seed also has a vehicle trace: a ped enters a car, drives
the roads, and gets out, while another ped shoots a van. The page
draws the car and the van. Each seed also has a behaviour trace:
civilians flee, a guard patrols, another guard shoots, and a
police officer warns then fires. Colour on that trace is the
role, and the mood is printed beside the action.

`Megacorp.Mission` ticks that cast, plus vehicles and items, until
every objective is met, every agent is dead, or the tick cap is
reached. The objectives are eliminate, acquire, persuade, and
evacuate. `bin/megacorp --mission 42` runs the street mission and
prints the result. `--ticks N` changes the cap. The page's Mission
trace shows the same run, with each objective flipping from open
to done. The page does not simulate.

Zoom and hover work in both views. If the browser will not read the
atlas pixels, hover uses the tile diamond and the map still loads.

Shells only, for later items: `Types`, `Assets`, `World`, `World.Gen`,
`Map.Gen`, `Mission.Gen`, `Agents`,
`Research`, `Session`, `Save`, `API`. There is no Syndicate asset
package.

## Licence

MIT. Copyright (c) 2026 Robert Boettcher. See `../LICENSE`. The
setting and the art are original. Headers in this directory say
`SPDX-License-Identifier: MIT`.
