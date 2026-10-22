#!/usr/bin/env bash
# MakeOfflineDownload.sh: builds single-file offline versions: out/Offline-@VER@-WasmGC.html and out/Offline-@VER@-JS.html.
# Obfuscated, everything inside one .html (compressed): open it from disk, no server or internet needed.
# Sound effects are re-encoded smaller; music/records are left out unless --music (then included at low bitrate).
# Usage: ./MakeOfflineDownload.sh [--wasm|--js] [--music] [--full-quality-sounds]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"; WS=$PWD
. patcher/patcher.cfg; . patcher/lib/common.sh; . patcher/lib/build.sh
TARGETS="wasm js"; MUSIC=0; FULLQ=0
for a in "$@"; do case "$a" in --wasm) TARGETS=wasm ;; --js) TARGETS=js ;; --music) MUSIC=1 ;; --full-quality-sounds) FULLQ=1 ;;
  -h|--help) sed -n 2,6p "$0"; exit 0 ;; *) die "unknown option $a" ;; esac; done
say "Minecraft $VER: offline download ($TARGETS)"
require_installed
ensure_sounds
step "Preparing offline sound set"
python3 patcher/lib/offline-sounds.py "$MUSIC" "$FULLQ"
mkdir -p out
for t in $TARGETS; do
  build_target $t
  PKG_NO_SOUNDS=1 package_target $t out/.stage-$t
  name=Offline-$VER-JS.html; [ $t = wasm ] && name=Offline-$VER-WasmGC.html
  step "Building $name"
  python3 patcher/lib/offline-html.py "$t" out/.stage-$t "out/$name" "$VER" "$TERSER"
  rm -rf out/.stage-$t
  ok "out/$name ($(du -h "out/$name" | cut -f1))"
done
say "Done"
echo "  Open the .html file in Chrome/Edge (WasmGC needs 137+). Keep it private: it contains Mojang code/assets built on this machine."
