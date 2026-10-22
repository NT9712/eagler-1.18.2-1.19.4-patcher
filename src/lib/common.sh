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
    MINGW*|MSYS*|CYGWIN*) notice_exit "Windows isn't supported directly. Install WSL (wsl --install, Ubuntu) and run this inside it." ;;
    *) notice_exit "Unsupported OS $(uname -s). Use Linux, macOS or Windows WSL." ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) ARCH=x64 ;; aarch64|arm64) ARCH=aarch64 ;;
    *) notice_exit "Unsupported CPU $(uname -m). Needs x86_64 or arm64." ;;
  esac
  export OS ARCH
}

ram_mb() {
  if [ "$OS" = linux ]; then
    local t; t=$(awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo)
    # respect a cgroup (container) memory limit when lower
    local c=/sys/fs/cgroup/memory.max; [ -r $c ] || c=/sys/fs/cgroup/memory/memory.limit_in_bytes
    if [ -r $c ]; then local l; l=$(cat $c); [[ "$l" =~ ^[0-9]+$ ]] && [ $((l/1048576)) -lt "$t" ] && t=$((l/1048576)); fi
    echo "$t"
  else echo $(( $(sysctl -n hw.memsize) / 1048576 )); fi
}
disk_free_mb() { df -Pk "$WS" | awk 'NR==2{print int($4/1024)}'; }

check_resources() {
  step "Checking this machine"
  RAM_MB=$(ram_mb); export RAM_MB
  local disk; disk=$(disk_free_mb)
  [ "$RAM_MB" -lt "$MIN_RAM_MB" ] && notice_exit "This machine has ${RAM_MB} MB of RAM. Building the port needs about 8 GB (min ${MIN_RAM_MB} MB): TeaVM and the decompiler each need ~5 GB of Java heap. Use a machine (or VM / WSL with more memory: .wslconfig memory=8GB) with at least 8 GB."
  [ "$disk" -lt "$MIN_DISK_MB" ] && notice_exit "Only ${disk} MB free on $(df -P "$WS" | awk 'NR==2{print $6}'). Needs about $((MIN_DISK_MB/1000)) GB free."
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
  if [ "$YES" != 1 ] && [ -t 0 ]; then
    read -r -p "Install missing packages with $mgr: $names ? [Y/n] " a; case "$a" in n*|N*) notice_exit "Missing dependencies: $names" ;; esac
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
  if [ ! -x tools/jdk/bin/java ]; then
    curl -fsSL "https://api.adoptium.net/v3/binary/latest/17/ga/$jos/$ARCH/jdk/hotspot/normal/eclipse" -o tools/cache/jdk17.tgz
    rm -rf tools/jdk && mkdir -p tools/jdk && tar xzf tools/cache/jdk17.tgz -C tools/jdk --strip-components=1 && rm tools/cache/jdk17.tgz
    if [ -d tools/jdk/Contents/Home ]; then mv tools/jdk tools/jdk-mac && mv tools/jdk-mac/Contents/Home tools/jdk && rm -rf tools/jdk-mac; fi
  fi
  if [ ! -x tools/gradle-8.10.2/bin/gradle ]; then
    curl -fsSL https://services.gradle.org/distributions/gradle-8.10.2-bin.zip -o tools/cache/gradle.zip
    (cd tools && unzip -q -o cache/gradle.zip) && rm tools/cache/gradle.zip
  fi
  if [ ! -x tools/node/bin/node ]; then
    local nos=linux narch=x64; [ $OS = mac ] && nos=darwin; [ $ARCH = aarch64 ] && narch=arm64
    local nv=v22.12.0
    curl -fsSL "https://nodejs.org/dist/$nv/node-$nv-$nos-$narch.tar.gz" -o tools/cache/node.tgz
    rm -rf tools/node && mkdir -p tools/node && tar xzf tools/cache/node.tgz -C tools/node --strip-components=1 && rm tools/cache/node.tgz
  fi
  export PATH="$WS/tools/node/bin:$PATH"
  if [ ! -x tools/npm/node_modules/.bin/terser ]; then
    mkdir -p tools/npm && (cd tools/npm && [ -f package.json ] || echo '{"private":true}' > package.json; npm i --silent --no-audit --no-fund terser@5.36.0 >/dev/null)
  fi
  [ -f tools/vineflower.jar ] || curl -fsSL https://repo1.maven.org/maven2/org/vineflower/vineflower/1.10.1/vineflower-1.10.1.jar -o tools/vineflower.jar
  [ -f tools/specialsource.jar ] || curl -fsSL https://repo1.maven.org/maven2/net/md-5/SpecialSource/1.11.4/SpecialSource-1.11.4-shaded.jar -o tools/specialsource.jar
  . scripts/env.sh
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
sha1of() { python3 -c 'import hashlib,sys; print(hashlib.sha1(open(sys.argv[1],"rb").read()).hexdigest())' "$1"; }

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
  . scripts/env.sh
  export PATH="$WS/tools/node/bin:$PATH" TERSER="$WS/tools/npm/node_modules/.bin/terser"
}
