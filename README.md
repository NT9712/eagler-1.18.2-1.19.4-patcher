# Minecraft browser port: patcher

Sets up the Minecraft Java **1.19.4** or **1.18.2** browser port (TeaVM: WasmGC + JavaScript, with a Sodium-style
renderer and FerriteCore memory savings) on your own machine.

**No Mojang code or assets are hosted here.** The patcher downloads the official client.jar, mappings, libraries and
assets straight from Mojang's servers onto your machine (SHA-1 checked), then remaps, decompiles and builds locally.
**We, the v3sp1e's studio's team, do not take responsibility for any inappropriate usage of this repo in any way,
shape or form. Note [MOJAND-READ.md](MOJANG-READ.md) for any legal complaints regarding this project.

## One-liner

```bash
# Minecraft 1.19.4
curl -fsSL https://raw.githubusercontent.com/NT9712/eagler-1.18.2-1.19.4-patcher/main/get.sh | bash -s -- 1.19.4
# Minecraft 1.18.2
curl -fsSL https://raw.githubusercontent.com/NT9712/eagler-1.18.2-1.19.4-patcher/main/get.sh | bash -s -- 1.18.2
```

This downloads the patcher into `./mc-<version>-web` and runs its `install.sh`. Or grab
`mc-<version>-web-patcher.zip` from [Releases](https://github.com/NT9712/eagler-1.18.2-1.19.4-patcher/releases), unzip it and
run `./install.sh`.

## After installing

| Command | Output |
|---|---|
| `./MakeDeploymentPackage.sh` | `out/deploy-<ver>-wasm/` and `out/deploy-<ver>-js/` (+ zips): obfuscated static sites for Netlify (drag onto app.netlify.com/drop) or localhost (`python3 serve.py`) |
| `./MakeOfflineDownload.sh` | `out/Offline-<ver>-WasmGC.html` and `out/Offline-<ver>-JS.html`: one obfuscated file each that runs from disk |

Add `--wasm` or `--js` to build only one. The offline file re-encodes sound effects smaller and leaves music out;
`--music` adds low-bitrate music, `--full-quality-sounds` keeps the original files.

## Requirements

- Linux, macOS (Homebrew) or Windows via WSL, x86_64 or arm64
- About 8 GB RAM and 9 GB free disk
- Missing tools (curl, unzip, zip, python3, git, ffmpeg) are installed with your package manager; JDK 17, Gradle and
  Node are downloaded into the project's `tools/` folder

`src/` holds the patcher scripts; `src/make-zip.sh <repo> <version> <outdir>` builds a release zip from a checkout of
the port.
