#!/usr/bin/env python3
"""minify-html.py INDEX TERSER: minifies + mangles every inline <script> (strips the dev comments) and collapses
whitespace between tags."""
import re, subprocess, sys, tempfile, os
p, terser = sys.argv[1], sys.argv[2]
if os.name == 'nt' and os.path.exists(terser + '.cmd'): terser += '.cmd'  # npm's Windows shim
s = open(p).read()
def mini(m):
    code = m.group(2)
    if not code.strip(): return m.group(0)
    with tempfile.NamedTemporaryFile('w', suffix='.js', delete=False) as f: f.write(code); name = f.name
    try:
        out = subprocess.run([terser, name, '-c', '-m'], capture_output=True, text=True, check=True).stdout
    finally: os.unlink(name)
    return m.group(1) + out.strip() + '</script>'
s = re.sub(r'(<script>)(.*?)</script>', mini, s, flags=re.S)
s = re.sub(r'<!--.*?-->', '', s, flags=re.S)
s = re.sub(r'>\s+<', '><', s)
open(p, 'w').write(s)
