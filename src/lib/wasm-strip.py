#!/usr/bin/env python3
"""wasm-strip.py FILE: removes the name and debug custom sections (function/type/local names, DWARF) from a wasm module in place,
so the shipped module carries no Java class/method names in its name section."""
import sys
p = sys.argv[1]; b = open(p, 'rb').read()
assert b[:4] == b'\0asm', 'not a wasm module'
def uleb(b, i):
    r = s = 0
    while True:
        x = b[i]; i += 1; r |= (x & 0x7f) << s; s += 7
        if x < 0x80: return r, i
out = bytearray(b[:8]); i = 8; dropped = 0
while i < len(b):
    sid = b[i]; size, j = uleb(b, i + 1); end = j + size
    name = ''
    if sid == 0:
        nl, k = uleb(b, j); name = b[k:k + nl].decode('utf-8', 'replace')
    # keep sections the TeaVM runtime reads (teavm.memoryRequirements, teavm.imports, dylink.0)
    if sid == 0 and (name == 'name' or name.startswith('.debug') or name in ('sourceMappingURL', 'producers')): dropped += end - i
    else: out += b[i:end]
    i = end
open(p, 'wb').write(out)
print('stripped %d bytes of custom sections' % dropped)
