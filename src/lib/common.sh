# Shared helpers for install.sh / MakeDeploymentPackage.sh / MakeOfflineDownload.sh (sourced, bash).
# Expects $WS (workspace root) and patcher/patcher.cfg already sourced.

if [ -t 1 ]; then B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; C=$'\e[36m'; N=$'\e[0m'; else B= G= Y= R= C= N=; fi
say()  { printf '\n%s== %s ==%s\n' "$B" "$*" "$N"; }
step() { printf '%s-> %s%s\n' "$C" "$*" "$N"; }
ok()   { printf '   %sok%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%sWARNING:%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '\n%sERROR:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }
notice_exit() { printf '\n%sNOTICE:%s %s\n\nNothing was changed. Exiting.\n' "$Y" "$N" "$*" >&2; exit 2; }

MIN_RAM_MB=${MIN_RAM_MB:-7400}     # ~8 GB machines report ~7.6-7.8 GiB; TeaVM + Vineflower need ~5 GB heap
MIN_DISK_MB=${MIN_DISK_MB:-9000}   # toolchain ~1 GB, Gradle caches ~1.5 GB, sounds 0.5 GB, builds ~3 GB

check_platform() {
  case "$(uname -s)" in
    Linux) OS=linux ;;
    Darwin) OS=mac ;;
    MINGW*|MSYS*) OS=windows ;;
    CYGWIN*) notice_exit "Cygwin isn't supported. On Windows run install.ps1 (it uses Git Bash), or use WSL." ;;
    *) notice_exit "Unsupported OS $(uname -s). Use Linux, macOS or Windows WSL." ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) ARCH=x64 ;; aarch64|arm64) ARCH=aarch64 ;;
    *) notice_exit "Unsupported CPU $(uname -m). Needs x86_64 or arm64." ;;
  esac
  export OS ARCH
  [ $OS = windows ] && win_setup
  return 0
}

# ---------------------------------------------------------------- Windows (Git Bash / MSYS2)
# The bash scripts run unchanged under Git for Windows' bash. win_setup fixes what differs: python3 is usually not a real
# command (only python / py, or the Microsoft Store stub), there's no zip, symlinks need privileges (MSYS copies
# instead), Python defaults to a legacy code page, and native programs (Java, Node, Python) need C:/ style paths.
winpath() { cygpath -m "$1"; }
find_python_win() {
  local c p
  if [ -n "${MC_PYTHON:-}" ] && [ -f "$MC_PYTHON" ]; then cygpath -u "$MC_PYTHON"; return 0; fi
  if command -v py >/dev/null 2>&1; then
    p=$(py -3 -c 'import sys; print(sys.executable)' 2>/dev/null | tr -d '\r') && [ -n "$p" ] && { cygpath -u "$p"; return 0; }
  fi
  for c in python python3; do
    for p in $(type -ap $c 2>/dev/null); do
      case "$p" in */WindowsApps/*) continue ;; esac
      p=$("$p" -c 'import sys; print(sys.executable)' 2>/dev/null | tr -d '\r') && [ -n "$p" ] && { cygpath -u "$p"; return 0; }
    done
  done
  return 1
}
win_setup() {
  local bin="$WS/tools/winbin" py=""
  rm -rf "$bin"; mkdir -p "$bin/py"
  export PATH="/mingw64/bin:/usr/bin:$PATH"
  py=$(find_python_win) || py=""
  # Python on Windows writes text files and stdout with CRLF and a legacy code page; make it behave like on Linux
  # (UTF-8, LF) so files and $(...) captures come out identical: PYTHONUTF8 + a sitecustomize that defaults newline='\n'.
  cp "$WS/patcher/lib/win_sitecustomize.py" "$bin/py/sitecustomize.py"
  export MSYS="${MSYS:-winsymlinks:native}" PYTHONUTF8=1 PYTHONIOENCODING=utf-8 CHERE_INVOKING=1
  export PYTHONPATH="$(winpath "$bin/py")${PYTHONPATH:+;$PYTHONPATH}"
  export PATH="$bin:$PATH"
  if [ -n "$py" ]; then
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$py" > "$bin/python3"; cp "$bin/python3" "$bin/python"
  fi
  # zip: Git for Windows has unzip but no zip; a tiny Python stand-in covers the "zip -qr9 OUT.zip PATH..." calls
  if ! command -v zip >/dev/null 2>&1 || [ "$(command -v zip)" = "$bin/zip" ]; then
    printf '#!/bin/sh\nexec python3 "%s" "$@"\n' "$WS/patcher/lib/winzip.py" > "$bin/zip"
  fi
  chmod +x "$bin"/* 2>/dev/null || true
}
# extract_zip ZIP DEST: unpack ZIP into DEST, dropping the archive's single top-level folder (like tar --strip-components=1)
extract_zip() {
  python3 - "$1" "$2" <<'PY'
import os, shutil, sys, zipfile
z, dest = sys.argv[1], sys.argv[2]
tmp = dest + '.unpack'
shutil.rmtree(tmp, ignore_errors=True)
zipfile.ZipFile(z).extractall(tmp)
top = os.listdir(tmp)
src = os.path.join(tmp, top[0]) if len(top) == 1 and os.path.isdir(os.path.join(tmp, top[0])) else tmp
os.makedirs(dest, exist_ok=True)
for n in os.listdir(src):
    shutil.move(os.path.join(src, n), os.path.join(dest, n))
shutil.rmtree(tmp, ignore_errors=True)
PY
}
# after sourcing scripts/env.sh: Java/Gradle read these themselves, so they must be Windows paths on Windows
fix_env_paths() {
  [ "${OS:-}" = windows ] || return 0
  local w; w=$(winpath "$WS")
  export JAVA_HOME="$w/tools/jdk" GRADLE_USER_HOME="$w/tools/gradle-home"
  export JAVA_TOOL_OPTIONS="-Djava.io.tmpdir=$w/tools/cache -Duser.home=$w/tools/cache"
  export PATH="$WS/tools/winbin:$WS/tools/node/bin:$WS/tools/jdk/bin:$PATH"
}

ram_mb() {
  if [ "$OS" = windows ]; then awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo
  elif [ "$OS" = linux ]; then
    local t; t=$(awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo)
    # respect a cgroup (container) memory limit when lower
    local c=/sys/fs/cgroup/memory.max; [ -r $c ] || c=/sys/fs/cgroup/memory/memory.limit_in_bytes
    if [ -r $c ]; then local l; l=$(cat $c); [[ "$l" =~ ^[0-9]+$ ]] && [ $((l/1048576)) -lt "$t" ] && t=$((l/1048576)); fi
    echo "$t"
  else echo $(( $(sysctl -n hw.memsize) / 1048576 )); fi
}
disk_free_mb() {
  if [ "$OS" = windows ]; then python3 -c 'import shutil,sys; print(shutil.disk_usage(sys.argv[1]).free // 1048576)' "$(winpath "$WS")"
  else df -Pk "$WS" | awk 'NR==2{print int($4/1024)}'; fi
}

check_resources() {
  step "Checking this machine"
  RAM_MB=$(ram_mb); export RAM_MB
  local disk; disk=$(disk_free_mb)
  [ "$RAM_MB" -lt "$MIN_RAM_MB" ] && notice_exit "This machine has ${RAM_MB} MB of RAM. Building the port needs about 8 GB (min ${MIN_RAM_MB} MB): TeaVM and the decompiler each need ~5 GB of Java heap. Use a machine (or VM / WSL with more memory: .wslconfig memory=8GB) with at least 8 GB."
  [ "$disk" -lt "$MIN_DISK_MB" ] && notice_exit "Only ${disk} MB free on the drive holding $WS. Needs about $((MIN_DISK_MB/1000)) GB free."
  ok "RAM ${RAM_MB} MB, free disk ${disk} MB, $OS/$ARCH, $(getconf _NPROCESSORS_ONLN 2>/dev/null || echo ?) CPUs"
}

# Java heap for a job that wants $1 GB, capped so the machine keeps ~2.5 GB for itself.
jheap() { local want=$(( $1 * 1024 )) cap=$(( RAM_MB - 2560 )); [ $cap -lt 3072 ] && cap=3072; [ $want -gt $cap ] && want=$cap; echo "${want}m"; }

SUDO=""
pkg_install() {  # pkg_install <apt names> | <dnf names> | <pacman names> | <zypper> | <apk> | <brew>
  local mgr="" names
  if   command -v apt-get >/dev/null; then mgr=apt;    names=$1
  elif command -v dnf     >/dev/null; then mgr=dnf;    names=$2
  elif command -v yum     >/dev/null; then mgr=yum;    names=$2
  elif command -v pacman  >/dev/null; then mgr=pacman; names=$3
  elif command -v zypper  >/dev/null; then mgr=zypper; names=$4
  elif command -v apk     >/dev/null; then mgr=apk;    names=$5
  elif command -v brew    >/dev/null; then mgr=brew;   names=$6
  else notice_exit "Missing tools ($1) and no supported package manager (apt, dnf, yum, pacman, zypper, apk, brew) was found. Install them yourself and rerun."
  fi
  if [ "$mgr" != brew ] && [ "$(id -u)" != 0 ]; then
    command -v sudo >/dev/null || notice_exit "Need root to install: $names. Install sudo or run as root."
    SUDO=sudo
  fi
  if [ "$YES" != 1 ] && [ "${PATCHER_YES:-0}" != 1 ] && [ -t 0 ]; then
    local a=""; read -r -p "Install missing packages with $mgr: $names ? [Y/n] " a || a=y   # EOF = default (yes)
    case "$a" in n*|N*) notice_exit "Missing dependencies: $names" ;; esac
  fi
  step "Installing $names ($mgr)"
  case $mgr in
    apt)    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -qq && $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $names ;;
    dnf)    $SUDO dnf install -y -q $names ;;
    yum)    $SUDO yum install -y -q $names ;;
    pacman) $SUDO pacman -Sy --needed --noconfirm $names ;;
    zypper) $SUDO zypper -q install -y $names ;;
    apk)    $SUDO apk add -q $names ;;
    brew)   brew install -q $names ;;
  esac
}

install_deps() {
  step "Checking dependencies"
  if [ "$OS" = mac ] && ! command -v brew >/dev/null; then
    notice_exit "Homebrew is needed on macOS to install tools. Install it from https://brew.sh and rerun."
  fi
  local miss=() t
  if [ "$OS" = windows ]; then
    for t in curl tar python3 git ffmpeg; do command -v $t >/dev/null || miss+=("$t"); done
    [ ${#miss[@]} -eq 0 ] || notice_exit "Missing: ${miss[*]}. On Windows run install.ps1 (or install.cmd): it installs Git, Python 3 and ffmpeg with winget (or choco / scoop), then runs this script in Git Bash."
    python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' || die "Python 3.8+ is required (found $(python3 -V))."
    ok "curl tar python3 git ffmpeg (Git Bash)"
    return 0
  fi
  for t in curl unzip zip tar python3 git ffmpeg; do command -v $t >/dev/null || miss+=("$t"); done
  [ "$OS" = mac ] && { brew list gnu-sed >/dev/null 2>&1 || miss+=(gnu-sed); brew list coreutils >/dev/null 2>&1 || miss+=(coreutils); }
  if [ ${#miss[@]} -gt 0 ]; then
    local m="${miss[*]}"
    local apt=${m/python3/python3 python3-venv}; apt="$apt ca-certificates"
    local alp=${m/python3/python3}; local pac=${m/python3/python}
    pkg_install "$apt" "$m" "$pac" "$m" "$alp bash" "${m/python3/python}"
    for t in "${miss[@]}"; do case $t in gnu-sed|coreutils) ;; *) command -v $t >/dev/null || die "$t still missing after install" ;; esac; done
  fi
  python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' || die "Python 3.8+ is required (found $(python3 -V))."
  if [ "$OS" = mac ]; then
    local bp; bp=$(brew --prefix)
    export PATH="$bp/opt/gnu-sed/libexec/gnubin:$bp/opt/coreutils/libexec/gnubin:$PATH"
  fi
  ok "curl unzip zip tar python3 git ffmpeg$( [ "$OS" = mac ] && echo ' gnu-sed coreutils')"
}

# JDK 17, Gradle 8.10.2, Node 22 (+ terser), Vineflower, SpecialSource: all local to tools/, nothing global.
setup_toolchain() {
  step "Toolchain (local to tools/)"
  mkdir -p tools/jdk tools/cache tools/gradle-home
  local jos=$OS; [ $OS = mac ] && jos=mac
  if [ $OS = windows ]; then
    # same JDK 17 / Gradle / Node versions as Linux and macOS, Windows zips (x64 builds; they also run on Windows arm64)
    if [ ! -f tools/jdk/bin/java.exe ]; then
      curl -fsSL "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse" -o tools/cache/jdk17.zip
      rm -rf tools/jdk && extract_zip tools/cache/jdk17.zip tools/jdk && rm tools/cache/jdk17.zip
    fi
    if [ ! -f tools/gradle-8.10.2/bin/gradle ]; then
      curl -fsSL https://services.gradle.org/distributions/gradle-8.10.2-bin.zip -o tools/cache/gradle.zip
      rm -rf tools/gradle-8.10.2 && extract_zip tools/cache/gradle.zip tools/gradle-8.10.2 && rm tools/cache/gradle.zip
    fi
    if [ ! -f tools/node/bin/node.exe ]; then
      local nv=v22.12.0
      curl -fsSL "https://nodejs.org/dist/$nv/node-$nv-win-x64.zip" -o tools/cache/node.zip
      rm -rf tools/node && extract_zip tools/cache/node.zip tools/node/bin && rm tools/cache/node.zip
    fi
  fi
  if [ $OS != windows ] && [ ! -x tools/jdk/bin/java ]; then
    curl -fsSL "https://api.adoptium.net/v3/binary/latest/17/ga/$jos/$ARCH/jdk/hotspot/normal/eclipse" -o tools/cache/jdk17.tgz
    rm -rf tools/jdk && mkdir -p tools/jdk && tar xzf tools/cache/jdk17.tgz -C tools/jdk --strip-components=1 && rm tools/cache/jdk17.tgz
    if [ -d tools/jdk/Contents/Home ]; then mv tools/jdk tools/jdk-mac && mv tools/jdk-mac/Contents/Home tools/jdk && rm -rf tools/jdk-mac; fi
  fi
  if [ $OS != windows ] && [ ! -x tools/gradle-8.10.2/bin/gradle ]; then
    curl -fsSL https://services.gradle.org/distributions/gradle-8.10.2-bin.zip -o tools/cache/gradle.zip
    (cd tools && unzip -q -o cache/gradle.zip) && rm tools/cache/gradle.zip
  fi
  if [ $OS != windows ] && [ ! -x tools/node/bin/node ]; then
    local nos=linux narch=x64; [ $OS = mac ] && nos=darwin; [ $ARCH = aarch64 ] && narch=arm64
    local nv=v22.12.0
    curl -fsSL "https://nodejs.org/dist/$nv/node-$nv-$nos-$narch.tar.gz" -o tools/cache/node.tgz
    rm -rf tools/node && mkdir -p tools/node && tar xzf tools/cache/node.tgz -C tools/node --strip-components=1 && rm tools/cache/node.tgz
  fi
  export PATH="$WS/tools/node/bin:$PATH"
  if [ ! -f tools/npm/node_modules/.bin/terser ]; then
    mkdir -p tools/npm && (cd tools/npm && [ -f package.json ] || echo '{"private":true}' > package.json; npm i --silent --no-audit --no-fund terser@5.36.0 >/dev/null)
  fi
  [ -f tools/vineflower.jar ] || curl -fsSL https://repo1.maven.org/maven2/org/vineflower/vineflower/1.10.1/vineflower-1.10.1.jar -o tools/vineflower.jar
  [ -f tools/specialsource.jar ] || curl -fsSL https://repo1.maven.org/maven2/net/md-5/SpecialSource/1.11.4/SpecialSource-1.11.4-shaded.jar -o tools/specialsource.jar
  . scripts/env.sh; fix_env_paths
  export PATH="$WS/tools/node/bin:$PATH" TERSER="$WS/tools/npm/node_modules/.bin/terser"
  ok "$(java -version 2>&1 | head -1), Gradle 8.10.2, Node $(node --version)"
}

# fetch_verified URL DEST SHA1
fetch_verified() {
  local url=$1 dest=$2 sha=$3
  if [ -f "$dest" ] && [ "$(sha1of "$dest")" = "$sha" ]; then ok "$dest (cached, sha1 ok)"; return; fi
  mkdir -p "$(dirname "$dest")"
  curl -fSL --retry 3 --progress-bar "$url" -o "$dest.part"
  local got; got=$(sha1of "$dest.part")
  [ "$got" = "$sha" ] || { rm -f "$dest.part"; die "SHA-1 mismatch for $url (got $got, expected $sha)"; }
  mv "$dest.part" "$dest"; ok "$dest (sha1 $sha)"
}
sha1of() { python3 -c 'import hashlib,sys; print(hashlib.sha1(open(sys.argv[1],"rb").read()).hexdigest())' "$1" | tr -d '\r'; }

# Gradle with heap sized to the machine (TeaVM WasmGC needs a deep stack: -Xss64m).
gradle_run() {
  local heap; heap=$(jheap 5)
  gradle --no-daemon --console=plain "-Dorg.gradle.jvmargs=-Xmx$heap -Xss64m -XX:+UseSerialGC -XX:MaxMetaspaceSize=512m" "$@"
}

require_installed() {
  [ -f "$WS/.patcher-installed" ] || die "Run ./install.sh first."
  check_platform; RAM_MB=$(ram_mb); export RAM_MB
  [ "$RAM_MB" -lt "$MIN_RAM_MB" ] && notice_exit "This machine has ${RAM_MB} MB of RAM; building needs about 8 GB."
  YES=1 install_deps >/dev/null
  . scripts/env.sh; fix_env_paths
  export PATH="$WS/tools/node/bin:$PATH" TERSER="$WS/tools/npm/node_modules/.bin/terser"
}
