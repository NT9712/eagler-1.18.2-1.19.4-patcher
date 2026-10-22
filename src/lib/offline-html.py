#!/usr/bin/env python3
"""offline-html.py TARGET(js|wasm) STAGE OUT.html VER TERSER: packs an obfuscated deployment folder (STAGE, from
package_target with PKG_NO_SOUNDS=1) plus the offline sound set (offline-sounds.py) into ONE self-contained .html.

Payloads sit in inert <script type="x-mc/p"> tags as base64 (code and the wasm module gzip-compressed first) and are
decoded on demand with fetch(data:) + DecompressionStream. A small boot script serves them to the game in place of
the network: window.fetch for probe.wasm / the zips / the asset index / sound objects, and the synchronous XHR
mcplatform.js uses for small sound files. The JS build's classes-NN.js chunks are decompressed and injected as
classic scripts in order (they share one global lexical scope), then main([]) starts the game."""
import base64, gzip, io, json, os, re, subprocess, sys, tempfile, zipfile, glob

target, stage, out, ver, terser = sys.argv[1:6]
ws = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
html = open(os.path.join(stage, 'index.html')).read()
iid = json.load(open(sorted(glob.glob(os.path.join(ws, 'meta/1.*.json')))[0]))['assetIndex']['id']
sounds = json.load(open(os.path.join(ws, 'tools/cache/offline-sounds/set.json')))  # name -> [orig sha1, file]

payloads = []  # (key, bytes, gzip?)
def add(key, data, z):
    payloads.append((key, data, z))

# ---- asset index + game-assets.zip limited to the sounds that are embedded, sizes = embedded file sizes
size_of = {name: os.path.getsize(os.path.join(ws, f)) for name, (h, f) in sounds.items()}
def fix_index(objs):
    res = {}
    for k, v in objs.items():
        if k == 'minecraft/sounds.json' or k.startswith('minecraft/sounds/'):
            if k not in sounds: continue
            v = dict(v, size=size_of[k])
        res[k] = v
    return res
full_index = json.load(open(os.path.join(ws, 'browser/web/assets/indexes/%s.json' % iid)))
add('assets/indexes/%s.json' % iid, json.dumps({'objects': fix_index(full_index['objects'])}).encode(), True)
ga_in = zipfile.ZipFile(os.path.join(stage, 'game-assets.zip'))
buf = io.BytesIO()
embedded_hashes = {h for h, f in sounds.values()}
with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as w:
    for i in ga_in.infolist():
        d = ga_in.read(i)
        if i.filename == 'indexes/%s.json' % iid:
            d = json.dumps({'objects': fix_index(json.loads(d)['objects'])}, indent=1, sort_keys=True).encode()
        elif i.filename == 'lazy-objects.txt':
            d = ''.join(h + '\n' for h in d.decode().split() if h in embedded_hashes).encode()
        w.writestr(i, d)
add('game-assets.zip', buf.getvalue(), False)
add('vanilla-resources.zip', open(os.path.join(stage, 'vanilla-resources.zip'), 'rb').read(), False)
done = set()
for name, (h, f) in sorted(sounds.items()):
    if h in done: continue
    done.add(h)
    add('assets/objects/%s/%s' % (h[:2], h), open(os.path.join(ws, f), 'rb').read(), False)  # raw: also served to the sync XHR path

# ---- code
def inline(src):
    return '<script>' + open(os.path.join(stage, src)).read().replace('</script', '<\\/script') + '</script>'
chunks = []
def repl(m):
    src = m.group(1)
    if re.match(r'classes-\d+\.js$', src):
        chunks.append(src); return ''
    return inline(src)
head, body = html.split('<body>', 1) if '<body>' in html else (html, '')
body = re.sub(r'<script src="([^"]+)"></script>', repl, body)
if target == 'js':
    assert chunks, 'no classes-NN.js chunks in the JS stage'
    for c in chunks:
        add(c, open(os.path.join(stage, c), 'rb').read(), True)
    # drop the page's own "on load -> main([])" starter: the boot script starts main after injecting the chunks
    starters = [m for m in re.finditer(r'<script>(.*?)</script>', body, re.S) if 'addEventListener("load"' in m.group(1)
                or "addEventListener('load'" in m.group(1)]
    assert len(starters) == 1, 'JS starter script not found (%d)' % len(starters)
    body = body.replace(starters[0].group(0), '')
else:
    add('probe.wasm', open(os.path.join(stage, 'probe.wasm'), 'rb').read(), True)

BOOT = r"""
(function(){
var P={},RF=window.fetch.bind(window),MIME={wasm:'application/wasm',json:'application/json',zip:'application/zip'};
document.querySelectorAll('script[type="x-mc/p"]').forEach(function(e){P[e.dataset.n]=e;});
function key(u){u=String(u&&u.url||u).replace(/[?#].*$/,'');var m=/assets\/(objects\/[0-9a-f]{2}\/[0-9a-f]{40}|indexes\/[^\/]+\.json)$/.exec(u);return m?'assets/'+m[1]:u.replace(/^.*\//,'');}
function bytes(k){var e=P[k];if(e._b)return e._b;var t=e.textContent;e.textContent='';
 var r=RF('data:application/octet-stream;base64,'+t);if(e.dataset.z)r=r.then(function(x){return new Response(x.body.pipeThrough(new DecompressionStream('gzip')));});
 return e._b=r.then(function(x){return x.arrayBuffer();});}
window.__mcBytes=bytes;window.__mcHas=function(k){return !!P[k];};
window.fetch=function(u,i){var k=key(u);if(!P[k]||(i&&i.method&&i.method!=='GET'))return RF(u,i);
 return bytes(k).then(function(b){return new Response(b,{status:200,headers:{'Content-Type':MIME[k.split('.').pop()]||'application/octet-stream'}});});};
var XO=XMLHttpRequest.prototype.open,XS=XMLHttpRequest.prototype.send;
XMLHttpRequest.prototype.open=function(m,u,a){var k=key(u);this.__k=(a===false&&P[k]&&!P[k].dataset.z)?k:null;return XO.apply(this,arguments);};
XMLHttpRequest.prototype.send=function(){var k=this.__k;if(!k)return XS.apply(this,arguments);var e=P[k];
 if(e._s===undefined){e._s=atob(e.textContent);e.textContent='';}
 Object.defineProperty(this,'status',{value:200});Object.defineProperty(this,'readyState',{value:4});Object.defineProperty(this,'responseText',{value:e._s});};
})();
"""
START_JS = r"""
(async function(){var st=document.getElementById('status'),c=%s;
for(var i=0;i<c.length;i++){if(st)st.textContent='Loading '+(i+1)+'/'+c.length+'…';
 var t=new TextDecoder().decode(await __mcBytes(c[i]));var s=document.createElement('script');s.text=t;document.body.appendChild(s);t=null;s.text='';}
if(st)st.textContent='Starting…';main([]);})().catch(function(e){console.error('[offline] '+(e&&e.stack||e));});
"""
def mini(code):
    with tempfile.NamedTemporaryFile('w', suffix='.js', delete=False) as f: f.write(code); n = f.name
    try: return subprocess.run([terser, n, '-c', '-m'], capture_output=True, text=True, check=True).stdout.strip()
    finally: os.unlink(n)

parts = []
for k, d, z in payloads:
    if z: d = gzip.compress(d, 9)
    parts.append('<script type="x-mc/p" data-n="%s"%s>%s</script>\n' % (k, ' data-z="1"' if z else '', base64.b64encode(d).decode()))
boot = '<script>' + mini(BOOT) + '</script>'
start = '<script>' + mini(START_JS % json.dumps(chunks)) + '</script>' if target == 'js' else ''
# body = canvas/status first, payloads, boot (patches fetch/XHR), then the page's scripts (mcplatform, runtime, loader)
m = re.search(r'<script', body)
pre, post = (body[:m.start()], body[m.start():]) if m else (body, '')
post = post.replace('</body>', start + '</body>', 1) if '</body>' in post else post + start
tmp = out + '.part'
with open(tmp, 'w') as f:
    f.write(head + '<body>' + pre)
    for p in parts: f.write(p)
    f.write(boot + post)
    if '</html>' not in post: f.write('</body></html>')
os.replace(tmp, out)
print('   %d payloads, %.1f MB' % (len(parts), os.path.getsize(out) / 1e6))
