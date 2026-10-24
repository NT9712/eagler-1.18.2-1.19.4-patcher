#!/bin/bash
# apply-patcher.sh DIR VER: puts the patcher scripts (this folder) into an unpacked mc-VER-web tree: patcher/ (cfg + lib),
# the Linux/macOS entry points (*.sh) and the Windows ones (*.ps1 + *.cmd). Used by make-zip.sh and by CI to test the
# scripts in this commit on top of a release zip.
set -euo pipefail
P=$(cd "$(dirname "$0")" && pwd); D=$1; VER=$2
mkdir -p "$D/patcher/lib"
cp "$P/cfg/$VER.cfg" "$D/patcher/patcher.cfg"
cp "$P"/lib/* "$D/patcher/lib/"
for f in install.sh MakeDeploymentPackage.sh MakeOfflineDownload.sh; do sed "s/@VER@/$VER/g" "$P/$f" > "$D/$f"; chmod +x "$D/$f"; done
for f in "$P"/windows/*.ps1 "$P"/windows/*.cmd; do sed "s/@VER@/$VER/g" "$f" > "$D/$(basename "$f")"; done
sed "s/@VER@/$VER/g" "$P/PATCHER.md" > "$D/PATCHER.md"
