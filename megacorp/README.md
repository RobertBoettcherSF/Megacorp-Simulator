# Megacorp Simulator 0.8.0

Headless Ada core for Megacorp Simulator. Version 0.8.0 adds
weapons, line of sight, and a shoot action (design items 1–8).
Version 0.6.1 keeps the browser page working when WebKit refuses
to read the atlas pixels. Later packages are still specs.

A browser page draws maps the Ada program has already exported. It
does not run the simulation. After this branch is on `master`:

<https://raw.githack.com/RobertBoettcherSF/ADA-Megacorp-Simulator/master/web/index.html>

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
tileset with `tools/gen_tileset.py`, runs `bin/megacorp` and
`bin/megacorp_smoke`, and rewrites `../web/data/` from the Ada map
export, including precomputed walk and drive paths and ped traces.
It also writes `dist/megacorp_v0.7.0.zip` for local use; that
archive is not a deliverable.

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

## What 0.8.0 contains

Real code: version, generator parameters (defaults 4 corporations,
40 regions, 128 by 128 city maps), the play-mode re-roll rule, a
monotonic clock, a log, `Megacorp.RNG`, and `Megacorp.Map`.

The RNG is xoshiro256\*\* seeded by SplitMix64. Child streams come
from the parent seed and a key (world, region, city, block, mission).

The map is one city. Each tile stores terrain, height, and walkable
and drivable flags. `Test_Layout` fills a road grid, pavement,
building blocks, and a river from the city-1 child of the given seed.
That layout is a stand-in until the city-block generator.

`Megacorp.Data.Virtual_FS` reads logical paths. The disk backend is
`Virtual_FS.Native`. `Megacorp.Assets.Placeholder` loads
`web/assets/tiles.json` through that interface and maps terrain plus
height to a tile id. The pictures are original, produced by
`tools/gen_tileset.py`. See `web/assets/LICENCE.txt`.

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
The page does not simulate.
Zoom and hover work in both views. If the browser will not read the
atlas pixels, hover uses the tile diamond and the map still loads.

Shells only, for later items: `Types`, `Assets`, `World`, `World.Gen`,
`Map.Gen`, `Behaviour`, `Vehicles`,
`Mission`, `Mission.Gen`, `Agents`, `Research`, `Session`, `Save`,
`API`. There is no Syndicate asset package.

## Licence

MIT. Copyright (c) 2026 Robert Boettcher. See `../LICENSE`. The
setting and the art are original. Headers in this directory say
`SPDX-License-Identifier: MIT`.
