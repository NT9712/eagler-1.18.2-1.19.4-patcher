# Build + package helpers (sourced after common.sh).

ensure_sounds() {
  step "Sound assets"
  python3 scripts/07-fetch-sounds.py --jobs 16 | tail -1
  # repack so game-assets.zip lists the sounds (install.sh --no-sounds packs without them)
  python3 scripts/06-pack-resources.py | tail -1
}

# TeaVM BALANCED builds (what the live sites ship). Outputs stay in browser/probe/build like a normal dev build.
build_js() {
  step "TeaVM JavaScript build (BALANCED, ~15-30 min)"
  gradle_run :browser:probe:generateJavaScript -PteavmOpt=BALANCED --continue > logs/teavm-js.log 2>&1 || true
  [ -s browser/probe/build/teavm-js/js/probe.js ] || die "JS build failed, see logs/teavm-js.log"
  MC_DIAG=0 bash scripts/04-assemble-web.sh > logs/assemble-js.log 2>&1 || die "JS assembly failed, see logs/assemble-js.log"
  ok "browser/probe/build/site"
}
build_wasm() {
  step "TeaVM WasmGC build (BALANCED, ~20-40 min)"
  gradle_run :browser:probe:generateWasmGC :browser:probe:copyWasmGCRuntime -Pwasmgc -PteavmWasmOpt=BALANCED --continue > logs/teavm-wasm.log 2>&1 || true
  [ -s browser/probe/build/teavm-wasmgc/wasm-gc/probe.wasm ] || die "WasmGC build failed, see logs/teavm-wasm.log"
  bash scripts/04-assemble-wasm.sh > logs/assemble-wasm.log 2>&1 || die "WasmGC assembly failed, see logs/assemble-wasm.log"
  ok "browser/probe/build/site-wasm"
}
# Rebuild only when the port sources changed since the last build of that target. The resource zips in browser/web are
# repacked by ensure_sounds on every run, so they don't count (package_target copies the current ones instead).
need_build() {  # need_build js|wasm
  local stamp=browser/probe/build/.patcher-$1 site=browser/probe/build/site; [ $1 = wasm ] && site=browser/probe/build/site-wasm
  [ -d $site ] && [ -f $stamp ] || return 0
  [ -n "$(find eagler browser/probe/src browser/probe/*.gradle browser/web browser/web-wasm scripts work -newer $stamp -type f \
          -not -path '*/build/*' -not -path 'browser/web/assets/*' -not -path 'browser/web/*.zip' 2>/dev/null | head -1)" ]
}
build_target() {  # build_target js|wasm
  if need_build $1; then
    [ $1 = js ] && build_js || build_wasm
    touch browser/probe/build/.patcher-$1
  else ok "$1 build is up to date"; fi
}

# package_target js|wasm OUTDIR: obfuscated, self-contained static site (index.html at its root).
package_target() {
  local t=$1 out=$2 site=browser/probe/build/site
  [ $t = wasm ] && site=browser/probe/build/site-wasm
  rm -rf "$out"; mkdir -p "$out"
  step "Packaging $t -> $out"
  cp -L $(ls -d $site/* | grep -v '/assets$') "$out/"
  cp browser/web/vanilla-resources.zip browser/web/game-assets.zip "$out/"   # current packs (sound list) even if the build was reused
  # first-run browser-friendly video options (same as the dist / live sites; ?vanillaOptions skips them)
  python3 patcher/lib/html-opts.py "$out/index.html" "$VER" "$t"
  # obfuscation
  if [ $t = js ]; then
    TERSER=$TERSER bash patcher/lib/mangle-js.sh "$out"
  else
    python3 patcher/lib/wasm-strip.py "$out/probe.wasm"
    $TERSER "$out/mcplatform.js" -c -m -o "$out/mcplatform.js.tmp" && mv "$out/mcplatform.js.tmp" "$out/mcplatform.js"
    $TERSER "$out/probe.wasm-runtime.js" -c -m -o "$out/rt.tmp" && mv "$out/rt.tmp" "$out/probe.wasm-runtime.js"
  fi
  python3 patcher/lib/minify-html.py "$out/index.html" "$TERSER"
  # sounds + asset index next to index.html (the client fetches assets/objects/<hh>/<sha1> lazily)
  mkdir -p "$out/assets/indexes"
  cp browser/web/assets/indexes/*.json "$out/assets/indexes/"
  [ "${PKG_NO_SOUNDS:-0}" = 1 ] || cp -R browser/web/assets/objects "$out/assets/objects"
  cp tools/bridge/serve.py "$out/serve.py"
  cat > "$out/_headers" <<'EOF'
/*.wasm
  Content-Type: application/wasm
/assets/objects/*
  Cache-Control: public, max-age=31536000, immutable
EOF
  cat > "$out/README.txt" <<EOF
Minecraft $VER browser port ($t build), built locally by the patcher. Contains Mojang code and assets
downloaded to the machine that built it: for your own private use only, don't redistribute.

Netlify: drag this folder onto https://app.netlify.com/drop (or: netlify deploy --prod --dir .)
Localhost: python3 serve.py   then open http://localhost:8000/
Multiplayer bridge: python3 serve.py --mc-server host:25565   (server needs online-mode=false)
EOF
  ok "$(du -sh "$out" | cut -f1) in $out"
}
