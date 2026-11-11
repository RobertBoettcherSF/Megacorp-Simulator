#!/bin/sh
# Build web/megacorp.wasm from the Ada world core.
# Compiler: AdaWebPack 22.1.0 llvm-gnat (not committed).
#   https://github.com/godunko/adawebpack/releases/tag/22.1.0
# Linker: wasm-ld from LLVM.
# Linked runtime: that release's libgnat.a,
#   GPL-3.0 WITH GCC-exception-3.1.
# The exception allows the combined module to be shipped under MIT.
# Our sources, the Text_IO stub, and gnat_stub.c are MIT.
# Details are in docs/DESIGN.md.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
repo=$(CDPATH= cd -- "$root/.." && pwd)
tool=${ADAWEB_ROOT:-/tmp/adawebpack/adawebpack}
if [ ! -x "$tool/bin/llvm-gcc" ]; then
   mkdir -p /tmp/adawebpack
   curl -fsSL -o /tmp/adawebpack/adawebpack-22.1.0.tar.gz \
      -L https://github.com/godunko/adawebpack/releases/download/22.1.0/adawebpack-22.1.0.tar.gz
   tar -xzf /tmp/adawebpack/adawebpack-22.1.0.tar.gz -C /tmp/adawebpack
fi
gcc="$tool/bin/llvm-gcc"
bind="$tool/bin/llvm-gnatbind"
work=$root/obj/wasm
rm -rf "$work"
mkdir -p "$work/rts/adainclude" "$work/rts/adalib"
cp -a "$tool/lib/rts-native/adalib/." "$work/rts/adalib/"
cp -a "$tool/lib/rts-native/adainclude/." "$work/rts/adainclude/"
cp "$root/wasm/runtime/"*.ads "$root/wasm/runtime/"*.adb \
   "$work/rts/adainclude/"
# Leave system.ads unchanged so the prebuilt runtime alis stay valid.
# No_Exception_Propagation stays. Save still compiles: a raise is a
# call, and a handler is deleted by the compiler. The files we write
# are well formed, so those paths are not taken.
cd "$work"
set -- -c -mtriple=wasm32-unknown-unknown -gnat2012 -gnata \
   --RTS="$work/rts" -I "$root/src" -I "$root/wasm"
"$gcc" "$@" -gnatg "$root/wasm/runtime/a-chahan.adb"
"$gcc" "$@" -gnatg "$root/wasm/runtime/a-textio.adb"
"$gcc" "$@" -gnatg "$root/wasm/runtime/s-exctab.adb"
"$gcc" "$@" -gnatg "$root/wasm/runtime/a-strunb.adb"
"$gcc" "$@" -gnatg "$root/wasm/runtime/a-contai.ads"
"$gcc" "$@" -gnatg "$root/wasm/runtime/a-coinve.ads"
"$gcc" "$@" -gnatg "$root/wasm/runtime/a-convec.adb"
"$gcc" "$@" -gnatg "$root/wasm/runtime/a-direct.adb"
"$gcc" "$@" -gnatg "$root/wasm/runtime/a-strbou.adb"
"$gcc" "$@" "$root/wasm/runtime/megacorp-host.adb"
"$gcc" "$@" "$root/src/megacorp.adb"
"$gcc" "$@" "$root/src/megacorp-parameters.adb"
"$gcc" "$@" "$root/src/megacorp-rng.adb"
"$gcc" "$@" "$root/src/megacorp-world.adb"
"$gcc" "$@" "$root/src/megacorp-world-gen.adb"
"$gcc" "$@" "$root/src/megacorp-world-campaign.adb"
"$gcc" "$@" "$root/src/megacorp-data.ads"
"$gcc" "$@" "$root/src/megacorp-assets.ads"
"$gcc" "$@" "$root/src/megacorp-data-virtual_fs.adb"
"$gcc" "$@" "$root/src/megacorp-data-virtual_fs-browser.adb"
"$gcc" "$@" "$root/src/megacorp-assets-import.adb"
"$gcc" "$@" "$root/wasm/runtime/megacorp-map.adb"
"$gcc" "$@" "$root/src/megacorp-weapons.adb"
"$gcc" "$@" "$root/src/megacorp-path.adb"
"$gcc" "$@" "$root/src/megacorp-peds.adb"
"$gcc" "$@" "$root/src/megacorp-vehicles.adb"
"$gcc" "$@" "$root/src/megacorp-map-gen.adb"
"$gcc" "$@" "$root/src/megacorp-shots.adb"
"$gcc" "$@" "$root/src/megacorp-actions.adb"
"$gcc" "$@" "$root/src/megacorp-behaviour.adb"
"$gcc" "$@" "$root/src/megacorp-mission.adb"
"$gcc" "$@" "$root/src/megacorp-mission-gen.adb"
"$gcc" "$@" "$root/src/megacorp-play.adb"
"$gcc" "$@" "$root/src/megacorp-agents.adb"
"$gcc" "$@" "$root/src/megacorp-research.adb"
"$gcc" "$@" "$root/src/megacorp-save.adb"
"$gcc" "$@" "$root/src/megacorp-session.adb"
"$gcc" "$@" "$root/src/megacorp-save-migrate.adb"
"$gcc" "$@" "$root/src/megacorp-save-log.adb"
"$gcc" "$@" "$root/src/megacorp-api.adb"
"$gcc" "$@" "$root/wasm/megacorp-wasm_store.adb"
"$gcc" "$@" "$root/wasm/megacorp_wasm.adb"
"$bind" -x megacorp_wasm.ali
"$gcc" "$@" b~megacorp_wasm.adb
clang --target=wasm32-unknown-unknown -c -O2 \
   -o gnat_stub.o "$root/wasm/gnat_stub.c"
wasm-ld --no-entry --export-memory --allow-undefined \
   --export=adainit --export=adafinal \
   --export=megacorp_init --export=megacorp_step \
   --export=megacorp_boot --export=megacorp_advance \
   --export=megacorp_reset \
   --export=megacorp_import_buffer --export=megacorp_import_capacity \
   --export=megacorp_commit_asset \
   --export=megacorp_command --export=megacorp_play \
   --export=megacorp_city --export=megacorp_city_size \
   --export=megacorp_brief --export=megacorp_brief_size \
   --export=megacorp_office --export=megacorp_office_size \
   --export=megacorp_state --export=megacorp_state_size \
   -z stack-size=2097152 \
   megacorp_wasm.o b~megacorp_wasm.o \
   megacorp.o megacorp-host.o megacorp-parameters.o megacorp-rng.o \
   megacorp-world.o megacorp-world-gen.o megacorp-world-campaign.o \
   megacorp-map.o megacorp-map-gen.o \
   megacorp-weapons.o megacorp-shots.o megacorp-path.o \
   megacorp-peds.o megacorp-vehicles.o \
   megacorp-actions.o megacorp-behaviour.o \
   megacorp-mission.o megacorp-mission-gen.o megacorp-play.o \
   megacorp-agents.o megacorp-research.o megacorp-session.o \
   megacorp-data-virtual_fs.o megacorp-data-virtual_fs-browser.o \
   megacorp-assets-import.o \
   megacorp-save.o megacorp-save-migrate.o megacorp-save-log.o \
   megacorp-api.o megacorp-wasm_store.o \
   a-chahan.o a-textio.o a-strunb.o a-strbou.o a-direct.o \
   a-convec.o s-exctab.o gnat_stub.o \
   "$tool/lib/rts-native/adalib/libgnat.a" \
   -o "$repo/web/megacorp.wasm"
echo "wrote $repo/web/megacorp.wasm"
