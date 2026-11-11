# Megacorp Simulator

A campaign of generated cities, written in Ada 2012. The browser page
draws what the Ada module computes. Version 0.28.0.

Play the current `master` build:

<https://raw.githack.com/RobertBoettcherSF/Megacorp-Simulator/master/web/index.html>

The design notes, including the morning-review list, are in
[docs/DESIGN.md](docs/DESIGN.md). The version history from 0.8.0 is
in [CHANGELOG.md](CHANGELOG.md).

## Build

Native, from `megacorp/`. This needs GNAT 12.3 and gprbuild. On
Ubuntu 24.04, pin `gnat-12` and `libgnat-12` to `12.3.0-17ubuntu1`.
The notes in [megacorp/README.md](megacorp/README.md) name the other
packages.

```sh
cd megacorp
./build.sh
```

That builds `bin/megacorp` and `bin/megacorp_smoke`, regenerates the
tileset, and rewrites `web/data/`. `bin/megacorp_smoke` exits 0 when
the checks pass. `bin/megacorp --engine-check` prints the seed 42
digests the module must match.

WebAssembly, from the same directory. `wasm/build.sh` downloads
AdaWebPack 22.1.0 if it is missing, then writes `web/megacorp.wasm`.

```sh
cd megacorp
bash wasm/build.sh
node wasm/check.mjs
```

Open `web/index.html` over HTTP. A `file://` URL cannot fetch the
module.

## Controls

The first visit shows five short tips. Skip stores that choice in
this browser.

- **Title.** New game, Continue (when a save exists), Settings, Credits.
- **New game.** Harbour (seed 42), Foundry (seed 7), or Marches (seed 100) locks the world. Free play takes a typed seed or a rolled one.
- **Map.** Click or tap a region for its briefing, then Start. Pause, 1×, 2×, and 4× advance the campaign. The side sheet is finances, a research grant (0, 40, or 80), the tree, and the roster. Hire costs 400. On a phone the sheet is at the bottom.
- **Mission.** Tap a person, then a tile, to walk. Tap an enemy to attack. Drag pans. A pinch, or + and −, zooms. Arrow keys pan.
- **Menu.** Resume, Save, or Quit to the title. Continue restores the save.
- A save that is missing or unreadable stays on the title and says so. New game is the way on.

## Licence

The code, tools, documents, and placeholder art written for this
project are MIT. Copyright (c) 2026 Robert Boettcher. See
[LICENSE](LICENSE).

`web/megacorp.wasm` is linked with the GNAT runtime from AdaWebPack.
That runtime is GPL-3.0 with the GCC Runtime Library Exception 3.1.
The exception lets the combined module be distributed under MIT. It
does not make this project GPL. The compiler and the runtime sources
are not in the repository. Details are in [NOTICE](NOTICE).

An imported game tree used to sit beside this code as design
inspiration. It was removed in version 0.8.0. This revision contains
none of that code and none of its files. Older git commits still do;
history was not rewritten.
