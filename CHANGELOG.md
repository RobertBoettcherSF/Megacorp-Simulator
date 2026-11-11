<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Robert Boettcher -->

# Changelog

Versions match the design item. Item 12 was skipped, so there is no
0.12.0. The reasoning for each call is in `docs/DESIGN.md`.

## 0.28.0 — polish

Opening funds 2400, upkeep 10 per living agent, a win of 1200 plus
the region's income, and player income at four times the atlas
formula. Seed 42 with grant 40 ends a quiet 30 days at 664, and a
scripted two-win 60 days at 1278. Five first-run tips, one button
size, larger phone type, and titles on the controls. A loading line
while the module starts. A corrupt or missing save, and a module
that fails to load, each show a message instead of a blank page.
The city view paints the camera's tiles and leaves the strategic
map alone between days.

## 0.27.0 — sound

Ada emits gunfire, hits, deaths, footsteps, clicks, win and loss,
a police alarm, and a border-fight blip. The page synthesizes them,
plus a short loop for the title, the map, and the city. No audio
files. Master, effects, and music persist.

## 0.26.0 — menus and briefing

Title, three fixed scenarios or a free-play seed, Continue, settings,
and credits. A briefing before the mission and a debrief after it.
Pause can resume, save, or quit. Ada chooses the screen.

## 0.25.0 — agents, research, economy

A named roster, a five-node research tree, and a purse separate from
campaign cash. Hiring costs 400. Debt stops hiring. Format version 3
migrates from v2 and v1. The page shows Finances, Research, and Roster.
The original purse numbers were revised in 0.28.0.

## 0.24.0 — world map

Regions in the owner's colour, a panel of Ada's figures, a corporation
list, Pause / 1× / 2× / 4×, and a ticker of border fights. A narrow
window uses a bottom sheet.

## 0.23.0 — playable mission

A region starts that city's recipe. Reach the zone to win. A timeout
or a lost squad loses. The result changes the owner or the unrest and
is stored in the delta log.

## 0.22.0 — input and tick

The page ticks a generated city inside the module on a fixed 33 ms
step. Pointer and key events are five integers. Ada selects, walks,
pans, and zooms.

## 0.21.0 — browser storage

The module reads and writes `slot.mgc` and `slot.log`. The page uses
OPFS, IndexedDB when that is unavailable, and a localStorage mirror.
Reload continues the day.

## 0.20.0 — WebAssembly

`web/megacorp.wasm` is the Ada world, built with AdaWebPack 22.1.0.
Seed 42 matches the native engine check. The linked runtime is
GPL-3.0 with the GCC Runtime Library Exception 3.1.

## 0.19.0 — migration

A version 1 save walks to version 2: a research total, default 0, and
a generator algorithm stamp. A newer format is refused. An old log
still replays.

## 0.18.0 — delta log

Checksummed lines since a snapshot. A torn final line is dropped.
The log folds into a new snapshot after 32 lines. A scenario cannot
re-roll. A visited region stays.

## 0.17.0 — save format

`MGC1`, a format version, and an FNV-1a checksum. The file stores the
seed, the day, and the fields play can change. Names and an untouched
city are rebuilt.

## 0.16.0 — corporation day

One strategic day: tax, defence, one attack, and revolts. The fight
is a formula. The player corporation does not take the turn.

## 0.15.0 — world generator

Forty named regions and four corporations from the world seed. Ped
ids run to 256 and vehicle ids to 64. The tick visits the people who
are present.

## 0.14.0 — mission recipes

A generated city gets civilians, guards, police, vehicles, and one of
briefing, snatch, or contract. Seeds 1 through 50 win.

## 0.13.0 — city generator

A 128×128 city: a road grid, four districts, parks, a river with
bridges, and one lake. Item 12 was skipped with 0.11.0, so the version
went from 0.11.0 to 0.13.0.

## 0.11.0 — mission loop

A mission ticks until the objectives are met, the squad is dead, or
the cap is reached. A lost squad cannot win on the same tick.

## 0.10.0 — behaviour

Civilians flee, panic spreads, guards patrol and shoot, police warn
for 12 ticks, and an agent persuades a neighbour.

## 0.9.0 — vehicles

A car and a van drive on roads. Peds enter and exit. A wreck stops
and ejects its passengers. The tileset is drawn by an Ada tool.

## 0.8.0 — licence and weapons

Our code is MIT, copyright Robert Boettcher. The imported trees are
gone from this revision. A pistol, an SMG, and a rifle, a hit roll,
and building line of sight.
