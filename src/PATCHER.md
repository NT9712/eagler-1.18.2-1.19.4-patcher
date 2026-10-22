# Minecraft @VER@ browser port: patcher

This folder is the port's source (platform layer, TeaVM transformers, Sodium-style renderer, FerriteCore memory
savings, build scripts) **without any Mojang code or assets**. `install.sh` downloads those directly from Mojang onto
your machine and builds the full workspace.

## Requirements
- Linux, macOS (with Homebrew) or Windows via WSL; x86_64 or arm64
- ~8 GB RAM and ~9 GB free disk (the scripts check and stop with a notice if not)
- Missing tools (curl, unzip, zip, python3, git, ffmpeg) are installed with your package manager. JDK 17,
  Gradle 8.10.2 and Node 22 are downloaded into `tools/` (nothing installed system-wide).

## Steps
1. `./install.sh`: checks the machine, fetches client.jar (@VER@, SHA-1 checked) from piston-data.mojang.com plus
   the mappings, libraries, asset index and sounds, remaps + decompiles the client and packs the resources.
   Options: `--yes`, `--no-decompile`, `--no-sounds`.
2. `./MakeDeploymentPackage.sh`: TeaVM BALANCED builds, obfuscated, one folder + zip per build:
   `out/deploy-@VER@-wasm/` (WasmGC, Chrome/Edge 137+) and `out/deploy-@VER@-js/` (JavaScript). Drag a folder onto
   https://app.netlify.com/drop, or run `python3 serve.py` inside it for localhost. `--wasm` / `--js` builds one.
3. `./MakeOfflineDownload.sh`: single-file, obfuscated `out/Offline-@VER@-WasmGC.html` and `out/Offline-@VER@-JS.html`
   that run from disk. Sound effects are re-encoded smaller; `--music` adds low-bitrate music,
   `--full-quality-sounds` keeps the original files.

Builds take roughly 20-40 minutes each. Everything Mojang that ends up in this folder or in `out/` was downloaded to
your machine by these scripts: keep it for your own use and don't redistribute it.

Licences: `eagler/sodium/LICENSE-SODIUM.txt` (LGPL-3.0), `eagler/ferrite/LICENSE-FERRITECORE.txt` (MIT).
