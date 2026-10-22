#!/usr/bin/env python3
"""fetch-mojang.py VER: Mojang mappings + the client's libraries, straight from Mojang/Maven, SHA-1 verified.
Reads meta/<VER>.json (already fetched and verified by install.sh). Same selection as the repo's own scripts:
1.18.2 = scripts/00-fetch-mc.py rules (LWJGL 3.2.2 only, slf4j-api 2.0.1), 1.19.4 = scripts/01-setup-toolchain.sh."""
import hashlib, json, os, sys, urllib.request

ver = sys.argv[1]
d = json.load(open('meta/%s.json' % ver))
os.makedirs('libs', exist_ok=True); os.makedirs('mappings', exist_ok=True)

def sha1(p):
    return hashlib.sha1(open(p, 'rb').read()).hexdigest()

def get(url, path, want=None):
    if os.path.exists(path) and (want is None or sha1(path) == want):
        return
    for attempt in range(3):
        try:
            data = urllib.request.urlopen(url, timeout=120).read(); break
        except Exception as e:
            if attempt == 2: raise SystemExit('download failed: %s (%s)' % (url, e))
    if want and hashlib.sha1(data).hexdigest() != want:
        raise SystemExit('SHA-1 mismatch: ' + url)
    open(path + '.part', 'wb').write(data); os.replace(path + '.part', path)
    print('   fetched', path)

m = d['downloads']['client_mappings']
get(m['url'], 'mappings/client.txt', m['sha1'])

n = 0
for l in d['libraries']:
    a = l.get('downloads', {}).get('artifact')
    if not a: continue
    name = os.path.basename(a['path'])
    if ver == '1.18.2':
        if l['name'].startswith('org.lwjgl:'):
            if not l['name'].endswith(':3.2.2'): continue
        elif any(r.get('os') for r in l.get('rules', [])): continue
        if name.startswith('slf4j-api-'): continue  # replaced by slf4j-api 2.0.1 below
    else:
        if 'natives' in l['name']: continue
    get(a['url'], 'libs/' + name, a.get('sha1')); n += 1
if ver == '1.18.2':
    get('https://repo1.maven.org/maven2/org/slf4j/slf4j-api/2.0.1/slf4j-api-2.0.1.jar', 'libs/slf4j-api-2.0.1.jar'); n += 1
print('   ok mappings/client.txt + %d libraries in libs/' % n)
