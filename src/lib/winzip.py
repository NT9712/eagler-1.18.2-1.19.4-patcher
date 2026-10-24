#!/usr/bin/env python3
"""winzip.py: stand-in for `zip -qr9 OUT.zip PATH...` on Windows (Git for Windows ships unzip but no zip)."""
import os, sys, zipfile

args = [a for a in sys.argv[1:]]
flags = ''.join(a[1:] for a in args if a.startswith('-') and len(a) > 1)
rest = [a for a in args if not (a.startswith('-') and len(a) > 1)]
if not rest:
    sys.exit('usage: zip [-qr9] OUT.zip PATH...')
out, paths = rest[0], rest[1:]
if not out.endswith('.zip') and not os.path.exists(out):
    out += '.zip'
level = int(next((c for c in reversed(flags) if c.isdigit()), '6'))
recurse = 'r' in flags
outabs = os.path.abspath(out)
with zipfile.ZipFile(out, 'a' if os.path.exists(out) else 'w', zipfile.ZIP_DEFLATED, compresslevel=level) as z:
    def add(p):
        if os.path.abspath(p) == outabs:
            return
        arc = os.path.normpath(p).replace('\\', '/')
        if os.path.isdir(p):
            if arc not in ('.', ''):
                z.write(p, arc + '/')
            if recurse:
                for n in sorted(os.listdir(p)):
                    add(os.path.join(p, n) if arc not in ('.', '') else n)
        else:
            z.write(p, arc)
    for p in paths:
        add(p)
