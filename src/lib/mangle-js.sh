#!/bin/bash
# mangle-js.sh DIR: obfuscates DIR/classes-*.js in place and minifies DIR/mcplatform.js.
# The chunks are classic scripts sharing one global scope, so top-level names are mangled with ONE name cache across
# all of them, in two passes (pass 1 learns every chunk's declarations so forward references resolve in pass 2).
# reserved.txt = browser globals + names the page/mcplatform.js define, which must never be used as mangled names
# (e.g. a top-level `let top` is a SyntaxError, and `self`/`MCP` are referenced across chunks).
set -e; DIR=$1; T=${TERSER:-terser}; HERE=$(cd "$(dirname "$0")" && pwd)
C=$(mktemp); CFG=$(mktemp --suffix=.json 2>/dev/null || mktemp); echo '{}' > $C
python3 - "$HERE/reserved.txt" > $CFG <<'P'
import json, sys
r = [l.strip() for l in open(sys.argv[1]) if l.strip()]
print(json.dumps({"compress": False, "mangle": {"toplevel": True, "reserved": r}, "output": {"comments": False}}))
P
n=$(ls $DIR/classes-*.js | wc -l); i=0
for pass in 1 2; do
  for f in $(ls $DIR/classes-*.js | sort); do
    i=$((i+1)); printf '\r   mangling pass %s: %s/%s ' $pass $(( (i-1) % n + 1 )) $n
    $T "$f" --config-file $CFG --name-cache $C -o "$f.tmp"
    if [ $pass = 2 ]; then mv "$f.tmp" "$f"; else rm -f "$f.tmp"; fi
  done
done
echo
rm -f $C $CFG
if [ -f $DIR/mcplatform.js ]; then $T $DIR/mcplatform.js -c -m -o $DIR/mcplatform.js.tmp && mv $DIR/mcplatform.js.tmp $DIR/mcplatform.js; fi
