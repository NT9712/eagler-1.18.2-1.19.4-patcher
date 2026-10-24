#!/usr/bin/env bash
# One-liner installer for the Minecraft browser-port patcher.
#   curl -fsSL https://raw.githubusercontent.com/NT9712/eagler-1.18.2-1.19.4-patcher/main/get.sh | bash -s -- 1.19.4
#   curl -fsSL https://raw.githubusercontent.com/NT9712/eagler-1.18.2-1.19.4-patcher/main/get.sh | bash -s -- 1.18.2
# Downloads the patcher zip from this repo's latest release into ./mc-<version>-web and runs its install.sh
# (extra arguments are passed on, e.g. --yes --no-decompile). Set MC_DIR to choose another folder, MC_NO_INSTALL=1 to only unpack.
# Windows: use get.ps1 (PowerShell) instead.
set -euo pipefail
REPO=NT9712/eagler-1.18.2-1.19.4-patcher
VER=${1:-}; [ $# -gt 0 ] && shift
# A usable terminal? `[ -r /dev/tty ]` isn't enough: without a controlling terminal (CI, Codespaces tasks, ssh -T)
# /dev/tty exists but can't be opened. PATCHER_YES=1 forces the non-interactive path (defaults, no questions).
tty_ok() { [ "${PATCHER_YES:-0}" != 1 ] && ( : < /dev/tty ) 2>/dev/null; }
if [ -z "$VER" ]; then
  if tty_ok; then read -r -p "Minecraft version to set up (1.18.2 or 1.19.4) [1.19.4]: " VER < /dev/tty || VER=""; fi
  VER=${VER:-1.19.4}
fi
case "$VER" in 1.18.2|1.19.4) ;; *) echo "Unknown version '$VER' (use 1.18.2 or 1.19.4)" >&2; exit 1 ;; esac
for t in curl unzip; do
  command -v $t >/dev/null && continue
  echo "-> installing $t"
  S=""; [ "$(id -u)" != 0 ] && command -v sudo >/dev/null && S=sudo
  if command -v apt-get >/dev/null; then $S apt-get update -qq && $S apt-get install -y -qq $t
  elif command -v dnf >/dev/null; then $S dnf install -y -q $t
  elif command -v pacman >/dev/null; then $S pacman -Sy --needed --noconfirm $t
  elif command -v zypper >/dev/null; then $S zypper -q install -y $t
  elif command -v apk >/dev/null; then $S apk add -q $t
  elif command -v brew >/dev/null; then brew install -q $t
  else echo "Please install $t and rerun." >&2; exit 1; fi
done
DIR=${MC_DIR:-$PWD/mc-$VER-web}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
echo "-> downloading the $VER patcher"
curl -fSL --retry 3 --progress-bar "https://github.com/$REPO/releases/latest/download/mc-$VER-web-patcher.zip" -o "$TMP/p.zip"
unzip -q "$TMP/p.zip" -d "$TMP"
mkdir -p "$DIR"; cp -R "$TMP/mc-$VER-web/." "$DIR/"
echo "-> patcher unpacked in $DIR"
# PATCHER_OVERLAY=DIR: put the patcher scripts from DIR (a checkout's src/) over the release ones (used by CI)
[ -n "${PATCHER_OVERLAY:-}" ] && bash "$PATCHER_OVERLAY/apply-patcher.sh" "$DIR" "$VER"
[ "${MC_NO_INSTALL:-0}" = 1 ] && exit 0
cd "$DIR"
if tty_ok; then exec ./install.sh "$@" < /dev/tty; else echo "-> no terminal: installing non-interactively (--yes)"; exec ./install.sh --yes "$@"; fi
