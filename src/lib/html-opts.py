#!/usr/bin/env python3
"""html-opts.py INDEX VER TARGET: browser-friendly first-run video options (as work/assemble-dist.sh does for the
live sites; ProbeMain.seedOptions only writes them when /game/options.txt doesn't exist; ?vanillaOptions skips them)
and a clean title."""
import re, sys
p, ver, t = sys.argv[1:4]
s = open(p).read()
opts = r'renderDistance:6\nsimulationDistance:5\nrenderClouds:"fast"\nentityShadows:false\nbiomeBlendRadius:1\nmipmapLevels:0\nparticles:1\ngraphicsMode:0\nao:false\n'
tag = "<head><script>if(window.mcOptions===undefined&&!/[?&]vanillaOptions\\b/.test(location.search))window.mcOptions='" + opts + "';</script>"
if 'window.mcOptions' not in s:
    s = s.replace('<head>', tag, 1)
s = re.sub(r'<title>.*?</title>', '<title>Minecraft %s%s</title>' % (ver, ' (WasmGC)' if t == 'wasm' else ''), s, 1)
open(p, 'w').write(s)
