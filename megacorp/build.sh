#!/bin/sh
# Build Megacorp Simulator 0.8.0, regenerate the tileset and web/data,
# and optionally pack sources plus the Linux x86_64 binaries. The zip
# is not a deliverable; the browser page reads the exported JSON.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
cd "$root"

if ! command -v gnat >/dev/null 2>&1; then
   echo "error: gnat is not on PATH (GNAT 12.3 required)" >&2
   exit 1
fi
if ! command -v gprbuild >/dev/null 2>&1; then
   echo "error: gprbuild is not on PATH" >&2
   exit 1
fi

version=$(gnat --version | head -n 1)
printf '%s\n' "$version"
case $version in
   *12.3*)
      ;;
   *)
      echo "error: GNAT 12.3 is required, got: $version" >&2
      exit 1
      ;;
esac

gprbuild -P megacorp.gpr -p

echo "---- tileset ----"
python3 "$root/../tools/gen_tileset.py"
echo "---- bin/megacorp ----"
./bin/megacorp
echo "---- export web/data ----"
./bin/megacorp --export "$root/../web/data"
echo "---- bin/megacorp_smoke ----"
./bin/megacorp_smoke

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
dest=$stage/megacorp_v0.8.0
mkdir -p "$dest/bin" "$dest/src" "$dest/apps"

cp README.md ../LICENSE .gitignore build.sh \
   megacorp.gpr megacorp_lib.gpr switches.gpr "$dest/"
cp src/*.ads src/*.adb "$dest/src/"
cp apps/*.ads apps/*.adb "$dest/apps/"
cp bin/megacorp bin/megacorp_smoke "$dest/bin/"
chmod 755 "$dest/build.sh" "$dest/bin/megacorp" "$dest/bin/megacorp_smoke"

mkdir -p dist
rm -f dist/megacorp_v0.8.0.zip
(
   cd "$stage"
   zip -r -X "$root/dist/megacorp_v0.8.0.zip" megacorp_v0.8.0
)
echo "wrote $root/dist/megacorp_v0.8.0.zip (optional, not a deliverable)"
