#!/usr/bin/env python3
"""offline-sounds.py MUSIC(0|1) FULLQ(0|1): picks and re-encodes the sound objects for the single-file offline build.

Sound effects: Ogg Vorbis q0 at 22.05 kHz (~4-5x smaller, from ~108 MB to ~25 MB). Music + records: left out unless
MUSIC=1, then mono q0 22.05 kHz (~65 MB instead of ~357 MB). FULLQ=1 keeps the original files.
Output: tools/cache/offline-sounds/<sha1-of-original>.<profile>.ogg and tools/cache/offline-sounds/set.json
({asset name: [original sha1, file]}). Re-encodes are cached between runs."""
import glob, json, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

music, fullq = sys.argv[1] == '1', sys.argv[2] == '1'
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
ver_json = sorted(glob.glob('meta/1.*.json'))[0]
iid = json.load(open(ver_json))['assetIndex']['id']
index = json.load(open('browser/web/assets/indexes/%s.json' % iid))['objects']
OUT = 'tools/cache/offline-sounds'; os.makedirs(OUT, exist_ok=True)

def is_music(k): return k.split('/')[2] in ('music', 'records')
want = {k: v for k, v in index.items()
        if k == 'minecraft/sounds.json' or (k.startswith('minecraft/sounds/') and (music or not is_music(k)))}

def job(item):
    k, v = item; h = v['hash']; src = 'browser/web/assets/objects/%s/%s' % (h[:2], h)
    if k.endswith('.json') or fullq:
        return k, h, src
    prof = 'm22q0' if is_music(k) else 's22q0'
    dst = '%s/%s.%s.ogg' % (OUT, h, prof)
    if not os.path.exists(dst):
        args = ['-ac', '1'] if is_music(k) else []
        r = subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', src, '-c:a', 'libvorbis', '-q:a', '0', '-ar', '22050'] + args
                           + ['-map_metadata', '-1', dst + '.part.ogg'], capture_output=True)
        if r.returncode != 0 or os.path.getsize(dst + '.part.ogg') >= os.path.getsize(src):
            if os.path.exists(dst + '.part.ogg'): os.remove(dst + '.part.ogg')
            try: os.symlink(os.path.abspath(src), dst)  # keep the original when re-encoding doesn't help
            except OSError: shutil.copyfile(src, dst)    # Windows without symlink rights
        else:
            os.replace(dst + '.part.ogg', dst)
    return k, h, dst

seen = {}
with ThreadPoolExecutor(os.cpu_count() or 2) as ex:
    res = list(ex.map(job, sorted(want.items())))
out = {k: [h, f] for k, h, f in res}
json.dump(out, open(OUT + '/set.json', 'w'))
total = sum(os.path.getsize(f) for _, f in {h: f for _, h, f in res}.items())
orig = sum(v['size'] for v in {v['hash']: v for v in want.values()}.values())
print('   ok %d sound files, %.1f MB (from %.1f MB)%s' % (len(out), total / 1e6, orig / 1e6, '' if music else ', music left out (--music adds it)'))
