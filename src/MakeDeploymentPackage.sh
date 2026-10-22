#!/usr/bin/env bash
# MakeDeploymentPackage.sh: builds obfuscated, ready-to-deploy static sites for Netlify or localhost,
# one per build: out/deploy-@VER@-wasm/ (WasmGC, fastest, Chrome/Edge 137+) and out/deploy-@VER@-js/ (JavaScript,
# any modern browser), each also zipped. Sounds included.
# Usage: ./MakeDeploymentPackage.sh [--wasm|--js] [--no-zip]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"; WS=$PWD
. patcher/patcher.cfg; . patcher/lib/common.sh; . patcher/lib/build.sh
TARGETS="wasm js"; ZIP=1
for a in "$@"; do case "$a" in --wasm) TARGETS=wasm ;; --js) TARGETS=js ;; --no-zip) ZIP=0 ;;
  -h|--help) sed -n 2,6p "$0"; exit 0 ;; *) die "unknown option $a" ;; esac; done
say "Minecraft $VER: deployment package ($TARGETS)"
require_installed
ensure_sounds
mkdir -p out
for t in $TARGETS; do
  build_target $t
  package_target $t out/deploy-$VER-$t
  if [ $ZIP = 1 ]; then rm -f out/deploy-$VER-$t.zip; (cd out/deploy-$VER-$t && zip -qr9 ../deploy-$VER-$t.zip .); ok "out/deploy-$VER-$t.zip ($(du -h out/deploy-$VER-$t.zip | cut -f1))"; fi
done
say "Done"
for t in $TARGETS; do echo "  out/deploy-$VER-$t/   Netlify: drag the folder onto app.netlify.com/drop   Local: (cd out/deploy-$VER-$t && python3 serve.py)"; done
echo "  These contain Mojang code/assets built on this machine: keep them private, don't redistribute."
