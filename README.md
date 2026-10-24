# Minecraft browser port: patcher

Sets up the Minecraft Java **1.19.4** or **1.18.2** browser port workspace consisting of a TeaVM port into WASM-GC
and JavaScript. There are certain optimisations including a slight port of Sodium and FerriteCore for speed.

**No Mojang code or assets are hosted here.** The patcher downloads the official client.jar, mappings, libraries and
assets straight from Mojang's servers onto your machine (SHA-1 checked), then remaps, decompiles and builds locally.

**We, the v3sp1e's studio's team, do not take responsibility for any inappropriate usage of this repo in any way,
shape or form. Note [MOJAND-READ.md](MOJANG-READ.md) for any legal complaints regarding this project.**

Demo at [1.18.2](https://mc-browser-1182-fireboy.netlify.app/) and [1.19.4](https://mc-browser-1194-fireboy.netlify.app/js/).
## To install

### Linux / macOS / WSL

```bash
# Minecraft 1.19.4
curl -fsSL https://raw.githubusercontent.com/NT9712/eagler-1.18.2-1.19.4-patcher/main/get.sh | bash -s -- 1.19.4
# Minecraft 1.18.2
curl -fsSL https://raw.githubusercontent.com/NT9712/eagler-1.18.2-1.19.4-patcher/main/get.sh | bash -s -- 1.18.2
```

### Windows (PowerShell)

```powershell
# Minecraft 1.19.4
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/NT9712/eagler-1.18.2-1.19.4-patcher/main/get.ps1))) 1.19.4
# Minecraft 1.18.2
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/NT9712/eagler-1.18.2-1.19.4-patcher/main/get.ps1))) 1.18.2
# or this, which asks for the version:
irm https://raw.githubusercontent.com/NT9712/eagler-1.18.2-1.19.4-patcher/main/get.ps1 | iex
```

Works in Windows PowerShell 5.1 and PowerShell 7, with no execution-policy change. It unpacks the patcher into
`.\mc-<version>-web` and runs `install.ps1`, which checks RAM/disk, installs **Git for Windows, Python 3 and ffmpeg**
with winget (falling back to Chocolatey or Scoop) if they're missing, then runs the same `install.sh` in Git Bash.
Afterwards, in that folder, use the `.cmd` versions of the scripts below (same options):

```powershell
.\MakeDeploymentPackage.cmd --js     # or --wasm, or nothing for both
.\MakeOfflineDownload.cmd
```

The `.cmd` files run their `.ps1` with `-ExecutionPolicy Bypass` (you can also double-click them), or run the `.sh`
scripts yourself from a Git Bash window.

### From the zip

Or just grab `mc-<version>-web-patcher.zip` from [Releases](https://github.com/NT9712/eagler-1.18.2-1.19.4-patcher/releases), unzip it and
run `./install.sh` (Windows: `install.cmd`).

## After installing

| Command | Output |
|---|---|
| `./MakeDeploymentPackage.sh` | `out/deploy-<ver>-wasm/` and `out/deploy-<ver>-js/` (+ zips): obfuscated static sites for Netlify (drag onto app.netlify.com/drop) or localhost (`python3 serve.py`) |
| `./MakeOfflineDownload.sh` | `out/Offline-<ver>-WasmGC.html` and `out/Offline-<ver>-JS.html`: one obfuscated file each that runs from disk |

Add `--wasm` or `--js` to build only one. The offline file re-encodes sound effects smaller and leaves music out;
`--music` adds low-bitrate music, `--full-quality-sounds` keeps the original files.

## Requirements

- Linux, macOS (Homebrew) or Windows 10/11 (PowerShell + Git Bash, or WSL), x86_64 or arm64
- About 8 GB RAM and 9 GB free disk
- Missing tools (curl, unzip, zip, python3, git, ffmpeg) are installed with your package manager (Windows: Git for
  Windows, Python 3 and ffmpeg via winget / Chocolatey / Scoop); JDK 17, Gradle and Node are downloaded into the
  project's `tools/` folder on every OS

`src/` holds the patcher scripts; `src/make-zip.sh <repo> <version> <outdir>` builds a release zip from a checkout of
the port. `.github/workflows/patcher.yml` runs the Windows path (get.ps1 → install.cmd → Git Bash) and the Linux path
for both versions on GitHub's runners, including a JS deployment build.
