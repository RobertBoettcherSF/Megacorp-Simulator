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
cd "$work"
set -- -c -mtriple=wasm32-unknown-unknown -gnat2012 -gnata \
   --RTS="$work/rts" -I "$root/src"
"$gcc" "$@" -gnatg "$root/wasm/runtime/a-chahan.adb"
"$gcc" "$@" -gnatg "$root/wasm/runtime/a-textio.adb"
"$gcc" "$@" "$root/src/megacorp.adb"
"$gcc" "$@" "$root/src/megacorp-parameters.adb"
"$gcc" "$@" "$root/src/megacorp-rng.adb"
"$gcc" "$@" "$root/src/megacorp-world.adb"
"$gcc" "$@" "$root/src/megacorp-world-gen.adb"
"$gcc" "$@" "$root/src/megacorp-world-campaign.adb"
"$gcc" "$@" "$root/src/megacorp-api.adb"
"$gcc" "$@" -I "$root/wasm" "$root/wasm/megacorp_wasm.adb"
"$bind" -x megacorp_wasm.ali
"$gcc" "$@" b~megacorp_wasm.adb
clang --target=wasm32-unknown-unknown -c -O2 \
   -o gnat_stub.o "$root/wasm/gnat_stub.c"
wasm-ld --no-entry --export-memory \
   --export=adainit --export=adafinal \
   --export=megacorp_init --export=megacorp_step \
   --export=megacorp_state --export=megacorp_state_size \
   -z stack-size=1048576 \
   megacorp_wasm.o b~megacorp_wasm.o \
   megacorp.o megacorp-parameters.o megacorp-rng.o \
   megacorp-world.o megacorp-world-gen.o megacorp-world-campaign.o \
   megacorp-api.o \
   a-chahan.o a-textio.o gnat_stub.o \
   "$tool/lib/rts-native/adalib/libgnat.a" \
   -o "$repo/web/megacorp.wasm"
echo "wrote $repo/web/megacorp.wasm"
