#!/bin/bash
# make-zip.sh REPO_DIR VER OUTDIR: builds OUTDIR/mc-VER-web-patcher.zip from the repo's committed files (HEAD, or $MAKEZIP_REF) minus everything
# Mojang (client, mappings, decompile, libraries, assets, compiled dists, screenshots) + the patcher scripts.
set -euo pipefail
P=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$1" && pwd); VER=$2; OUT=$(mkdir -p "$3" && cd "$3" && pwd)
S=$(mktemp -d); D=$S/mc-$VER-web
mkdir -p "$D"
EXCL='^(original|remapped|mappings|decompiled|libs|dist)/|^meta/assets/|^meta/[^/]+\.json$|^browser/web/assets/|^browser/web/[^/]+\.zip$|\.(png|jpg|class|ogg|wasm|jar)$'
REF=${MAKEZIP_REF:-HEAD}   # committed files only: uncommitted work in the checkout never ends up in a release
(cd "$REPO" && git ls-tree -r --name-only -z "$REF" | tr '\0' '\n' | grep -Ev "$EXCL" | grep -v '^tools/eaglerxserver-patch/build/' > "$S/files")
# keep TeaVM's own (Apache-2.0) jars that the build uses
(cd "$REPO" && git ls-tree -r --name-only "$REF" -- tools/teavm-cli.jar tools/teavm-src | grep -E '^tools/(teavm-cli|teavm-src/.*)\.jar$' >> "$S/files")
(cd "$REPO" && git archive --format=tar "$REF") | (cd "$D" && tar xf - -T "$S/files")
"$P/apply-patcher.sh" "$D" "$VER"
# safety net: nothing Mojang-shaped may be in the zip
bad=$(cd "$D" && find . \( -name '*.class' -o -name 'client.jar' -o -name 'client.txt' -o -name '*.ogg' -o -name '*.png' -o -path './decompiled*' -o -path './libs/*' \) | head -5)
[ -z "$bad" ] || { echo "Mojang-looking files in patcher: $bad"; exit 1; }
if grep -rIl --exclude-dir=.git -E 'gh[pousr]_[A-Za-z0-9]{30,}|nfp_[A-Za-z0-9]{30,}|github_pat_' "$D" >/dev/null; then echo "token-like string in patcher"; exit 1; fi
rm -f "$OUT/mc-$VER-web-patcher.zip"; (cd "$S" && zip -qr9 "$OUT/mc-$VER-web-patcher.zip" "mc-$VER-web")
echo "$OUT/mc-$VER-web-patcher.zip $(du -h "$OUT/mc-$VER-web-patcher.zip" | cut -f1) ($(wc -l < "$S/files") files)"
rm -rf "$S"
