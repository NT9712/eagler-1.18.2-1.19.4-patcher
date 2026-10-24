#!/usr/bin/env bash
# install.sh: sets up the Minecraft @VER@ browser-port workspace from this patcher.
# No Mojang code or assets ship with the patcher. This script downloads them straight from Mojang
# (piston-data / piston-meta / libraries.minecraft.net / resources.download.minecraft.net) onto YOUR machine,
# verifies their SHA-1, remaps and decompiles the client, and leaves a workspace laid out like the private repo.
#
# Usage: ./install.sh [--yes] [--no-decompile] [--no-sounds] [--client-url=URL]
#   --yes             don't ask before installing missing system packages
#   --no-decompile    skip the Vineflower decompile (decompiled/ is reference only; the build doesn't need it)
#   --no-sounds       skip the ~470 MB of sound objects (the Make* scripts will fetch them when needed)
#   --client-url=URL  take client.jar from this piston-data URL (or $MC_CLIENT_URL); its SHA-1 must still match
#   On Windows run install.ps1 / install.cmd instead: it installs Git Bash, Python and ffmpeg, then runs this script.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
WS=$PWD
. patcher/patcher.cfg
. patcher/lib/common.sh

YES=0; DECOMPILE=1; SOUNDS=1
for a in "$@"; do case "$a" in
  --yes|-y) YES=1 ;; --no-decompile) DECOMPILE=0 ;; --no-sounds) SOUNDS=0 ;; --client-url=*) MC_CLIENT_URL=${a#*=} ;;
  -h|--help) sed -n 2,14p "$0"; exit 0 ;; *) die "unknown option $a" ;; esac; done

CLIENT_URL=${MC_CLIENT_URL:-$CLIENT_URL}
case "$CLIENT_URL" in https://piston-data.mojang.com/*|https://launcher.mojang.com/*) ;; *) die "client URL must be a Mojang piston-data URL: $CLIENT_URL" ;; esac
say "Minecraft $VER browser port: workspace setup"
check_platform
check_resources
install_deps
setup_toolchain

# ---------------------------------------------------------------- Mojang inputs (fetched, never shipped)
mkdir -p original mappings libs remapped decompiled meta logs work tools/cache
step "Version metadata"
fetch_verified "$VERSION_JSON_URL" "meta/$VER.json" "$VERSION_JSON_SHA1"
[ -n "${MANIFEST_FILE:-}" ] && { [ -f "$MANIFEST_FILE" ] || curl -fsSL "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json" -o "$MANIFEST_FILE"; }

step "client.jar ($CLIENT_URL)"
fetch_verified "$CLIENT_URL" original/client.jar "$CLIENT_SHA1"

step "Mappings and libraries"
python3 patcher/lib/fetch-mojang.py "$VER"

step "Remapping client.jar to Mojang names (SpecialSource)"
if [ ! -s remapped/client-mojmap.jar ]; then
  java -Xmx$(jheap 3) -jar tools/specialsource.jar --in-jar original/client.jar --out-jar remapped/client-mojmap.jar \
    --srg-in mappings/client.txt -q
fi
ok "remapped/client-mojmap.jar"

if [ $DECOMPILE = 1 ]; then
  step "Decompiling (Vineflower, a few minutes)"
  if [ ! -f decompiled/.done ]; then
    LIBS=$(ls libs/*.jar | sed 's/^/-e=/' | tr '\n' ' ')
    # shellcheck disable=SC2086
    java -Xmx$(jheap 5) -jar tools/vineflower.jar -dgs=1 -rsy=1 -log=WARN $LIBS remapped/client-mojmap.jar decompiled/ \
      > logs/decompile.log 2>&1 || die "decompile failed, see logs/decompile.log"
    touch decompiled/.done
  fi
  ok "decompiled/ ($(find decompiled -name '*.java' | wc -l | tr -d ' ') java files)"
fi

if [ $SOUNDS = 1 ]; then
  step "Sound assets (from resources.download.minecraft.net, ~470 MB, resumable)"
  python3 scripts/07-fetch-sounds.py --jobs 16 | tail -2
else
  python3 scripts/07-fetch-sounds.py --only-sounds-json | tail -1
fi

step "Packing game resources"
MC_LAZY_SOUNDS=1 python3 scripts/06-pack-resources.py 2>/dev/null || MC_LAZY_SOUNDS=0 python3 scripts/06-pack-resources.py
ok "browser/web/vanilla-resources.zip, browser/web/game-assets.zip"

step "Warming up Gradle (compiles the port modules once)"
gradle_run --offline classes >/dev/null 2>&1 || gradle_run classes > logs/gradle-warmup.log 2>&1 || warn "Gradle warm-up failed (see logs/gradle-warmup.log); the Make scripts will retry."

touch .patcher-installed
say "Done. Workspace ready in $WS"
if [ "$OS" = windows ]; then cat <<EOF

  Next (PowerShell or cmd, in this folder):
    .\\MakeDeploymentPackage.cmd          obfuscated WasmGC and JS folders (+ .zip) for Netlify or localhost
    .\\MakeOfflineDownload.cmd            single-file offline .html (WasmGC and JS)
    Add --wasm or --js to build only one. Builds take ~20-40 min each on a typical machine.

  Everything Mojang in this folder came from Mojang's servers to this machine. Don't publish this folder.
EOF
exit 0; fi
cat <<EOF

  Next:
    ./MakeDeploymentPackage.sh            obfuscated WasmGC and JS folders (+ .zip) for Netlify or localhost
    ./MakeOfflineDownload.sh              single-file offline .html (WasmGC and JS)
    Add --wasm or --js to build only one. Builds take ~20-40 min each on a typical machine.

  Everything Mojang in this folder came from Mojang's servers to this machine. Don't publish this folder.
EOF
