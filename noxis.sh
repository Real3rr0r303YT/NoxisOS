#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Noxis OS – Copyright (C) 2026 3rr0r (Real3rr0r303YT) – Made by 3rr0r303YT on TikTok
# ============================================================
#  Noxis OS – build tool (Android 17 / LineageOS 24.0)
#  Device: Nothing Phone (3a) / (3a) Pro  –  "asteroids"
#
#  ./noxis.sh check              Check the PC (RAM, disk, tools)
#  ./noxis.sh sync               Fetch the source (--depth=1, ~110 GB) + add Noxis
#  ./noxis.sh apps               Own apps, IronFox, F-Droid, Aurora, Termux, ClamAV DB, KSU modules, Mullvad, Tor, KernelSU manager
#  ./noxis.sh blobs <ota|dump>   Extract the vendor files from a Nothing OS OTA or dump
#  ./noxis.sh blobs <ota> --regen
#                                Same, but rewrite the file list from the dump -
#                                needed when the dump is a different Nothing OS
#                                version than the device tree expects
#  ./noxis.sh keys               Create your own signing keys
#  ./noxis.sh build              Compile (user build, KernelSU in the kernel)
#  ./noxis.sh eta                How long the running build still needs (2nd terminal)
#  ./noxis.sh opsec              Check the built image against the OPSEC rules
#  ./noxis.sh sign               Sign → OTA + images → Desktop, delete out/
#  ./noxis.sh cleanup            ROM to the Desktop (NOXIS_KEEP_OUT=0 also deletes out/)
#  ./noxis.sh flash              Install on the phone (guided, bootloader stays unlocked)
#  ./noxis.sh postinstall        After the first boot: Termux/Tor/... via adb
#  ./noxis.sh ksu                KernelSU manager matching the kernel (installs via adb)
#  ./noxis.sh publish            Upload the OTA as a GitHub release → phone: Settings → System → Updater
#  ./noxis.sh all <ota.zip>      sync → apps → blobs → keys → build → sign
#
#  Repair / debugging (no rebuild needed):
#  ./noxis.sh direct             Write only the system partitions again (fastbootd)
#  ./noxis.sh sysextfix          Add missing privapp permissions to system_ext.img
#  ./noxis.sh debugadb           ADB from the first second of boot (to read logcat)
# ============================================================
set -Eeuo pipefail
# If the script stops somewhere without its own message, show where - line
# and command. Otherwise it ends silently and the next step carries on with
# an old state as if nothing happened.
trap 'printf "\033[1;31m[error]\033[0m unexpected stop in noxis.sh line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

NOXIS="$(cd "$(dirname "$0")" && pwd)"
SRC="${NOXIS_SRC:-$HOME/noxis-src}"
KEYS="${NOXIS_KEYS:-$HOME/.noxis-keys}"
# Not called OUT: LineageOS' envsetup.sh sets OUT to out/target/product/...
# and would redirect the finished ROM there (which gets deleted afterwards).
REL="${NOXIS_OUT:-$NOXIS/release}"
BRANCH="lineage-24.0"
DEVICE="asteroids"
# NOXIS_DEBUG=1: userdebug + ADB from the first boot without the approval
# dialog - only for debugging (boot loops), never for daily use.
if [ "${NOXIS_DEBUG:-0}" = 1 ]; then VARIANT="${NOXIS_VARIANT:-userdebug}"; else VARIANT="${NOXIS_VARIANT:-user}"; fi
export NOXIS_DEBUG="${NOXIS_DEBUG:-0}"
SUBJECT="${NOXIS_SUBJECT:-/C=DE/O=Noxis OS/OU=Noxis/CN=Noxis OS}"
# KernelSU: the kernel tree brings its own copy (crDroid, often an unreleased
# main-branch state). By default it is replaced with this official release,
# so kernel and the officially signed manager of the same release match
# exactly. NOXIS_KSU_PIN=none keeps the kernel tree's own copy.
KSU_PIN="${NOXIS_KSU_PIN:-v3.3.1}"
KSU_TAG="${NOXIS_KSU_TAG:-}"   # empty = the pinned release, or the one matching the kernel
# Old (German) variable names keep working
NOXIS_OTHER_FIRMWARE="${NOXIS_OTHER_FIRMWARE:-${NOXIS_ANDERER_STAND:-0}}"

c()    { printf '\033[38;5;111m[noxis]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m[error]\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is missing – $2"; }
confirm() { read -rp "$1 [yes/N] " a; case "${a,,}" in yes|y|ja|j) return 0 ;; *) return 1 ;; esac; }

envsetup() {
  cd "$SRC"
  # LineageOS' scripts let commands fail on purpose; the trap above would
  # raise false alarms there. From here on die() reports real errors.
  trap - ERR
  set +Eu
  # shellcheck disable=SC1091
  source build/envsetup.sh >/dev/null
  breakfast "$DEVICE" "$VARIANT" >/dev/null || die "breakfast $DEVICE $VARIANT failed"
  set -u
}

# The Soong analysis is a single process with 15-20 GB. With little RAM the
# kernel kills it ("signal: killed") even when the swap file is free - it is
# too slow. Compressed swap in RAM (zram) is enough. Lasts until reboot; if
# it is already there nothing happens.
zram_on() {
  local ram
  ram=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
  [ "$ram" -ge 32 ] && return 0
  if grep -q '^/dev/zram' /proc/swaps; then
    c "zram swap already active"
  else
    c "Little RAM ($ram GB): setting up 20 GB zram swap (sudo password)"
    local z
    sudo modprobe zram \
      && z=$(sudo zramctl --find --size 20G --algorithm zstd) \
      && sudo mkswap "$z" >/dev/null && sudo swapon -p 100 "$z" \
      || { warn "zram failed – the analysis may get killed (signal: killed)"; return 0; }
  fi
  sudo sysctl -q vm.swappiness=180 vm.watermark_scale_factor=200 vm.page-cluster=0 || true
}

# Some projects (e.g. external/chromium-webview) are stored with Git LFS.
# Without git-lfs during the sync only small text pointers end up there
# instead of the APKs, and the build fails hours later
# ("aapt2 dump badging ... webview.apk").
lfs_fetch() {
  command -v git-lfs >/dev/null 2>&1 || die "git-lfs is missing.
       Gentoo: sudo emerge --ask dev-vcs/git-lfs   Debian/Ubuntu: sudo apt install git-lfs"
  git lfs install --skip-repo >/dev/null
  c "Fetching Git LFS files (WebView etc.)"
  ( cd "$SRC" && repo forall -j4 -c 'git lfs pull >/dev/null 2>&1 || true' )
}

# Before building: are there still LFS pointers instead of real files?
lfs_check() {
  local apk="$SRC/external/chromium-webview/prebuilt/arm64/webview.apk"
  if [ -f "$apk" ] && head -c 40 "$apk" | grep -q "git-lfs"; then
    warn "WebView is only a Git LFS pointer – fetching the real files"
    lfs_fetch
    head -c 40 "$apk" | grep -q "git-lfs" && die "WebView still not downloaded – check the internet connection, then try again"
  fi
  return 0
}

# Pre-signed third-party APKs (Tor Browser, Mullvad ...) have to go into the
# system unchanged. Android 17 requires uncompressed .so libraries for that;
# some vendors ship them compressed ("Contains compressed JNI libraries").
# Repacking would destroy their signature. Such apps therefore do not go
# into the image but are installed via adb after flashing
# (./noxis.sh postinstall) - they stay originally signed and updatable.
POST="$NOXIS/postinstall"
apks_check() {
  local d name apk
  for d in "$SRC/vendor/noxis/prebuilt"/*/; do
    name=$(basename "$d"); apk="$d$name.apk"
    [ -f "$apk" ] && grep -qs "preprocessed: true" "$d/Android.bp" || continue
    if unzip -v "$apk" 2>/dev/null | awk '$NF ~ /^lib\/.*\.so$/ && $2 != "Stored" {f=1} END {exit !f}'; then
      mkdir -p "$POST"
      cp -f "$apk" "$POST/$name.apk"
      rm -rf "$d" "$NOXIS/vendor/noxis/prebuilt/$name"
      warn "$name has compressed libraries – it does not go into the image,
       it is installed after flashing with ./noxis.sh postinstall"
    fi
  done
  return 0
}

cmd_postinstall() {
  need adb "install android-tools"
  # old folder name from earlier versions
  [ -d "$NOXIS/nachinstallieren" ] && { mkdir -p "$POST"; mv -n "$NOXIS/nachinstallieren"/*.apk "$POST"/ 2>/dev/null || true; }
  compgen -G "$POST/*.apk" >/dev/null || compgen -G "$POST/modules/*.zip" >/dev/null \
    || { c "Nothing to install"; return 0; }
  c "Connect the phone with USB debugging (Settings → Developer options)"
  adb wait-for-device
  local a z
  for a in "$POST"/*.apk; do
    [ -f "$a" ] || continue
    c "installing $(basename "$a" .apk)"
    adb install -r "$a" || warn "$(basename "$a") failed"
  done
  # KernelSU modules: copy to Download, then install with root. adb shell
  # only gets root after you allow "Shell" in the KernelSU app once.
  for z in "$POST"/modules/*.zip; do
    [ -f "$z" ] || continue
    adb push "$z" "/sdcard/Download/$(basename "$z")" >/dev/null
    if adb shell "su -c '/data/adb/ksud module install /sdcard/Download/$(basename "$z")'" ; then
      c "KernelSU module $(basename "$z" .zip) installed – reboot the phone"
    else
      warn "KernelSU module $(basename "$z" .zip): no root for adb.
       Either: KernelSU app → Superuser → Shell → allow, then ./noxis.sh postinstall again
       Or:     KernelSU app → Modules → Install → Download/$(basename "$z")"
    fi
  done
}

# ------------------------------------------------------------ check
cmd_check() {
  local ram disk
  ram=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
  disk=$(df -BG --output=avail "$(dirname "$SRC")" | tail -1 | tr -dc 0-9)
  c "RAM: ${ram} GB (32+ recommended, 16 GB only with 32 GB swap)"
  # Source already synced → only out/ still needs space
  local want=400 min=350 what="110 GB source, the rest out/"
  [ -d "$SRC/.repo" ] && { want=150; min=150; what="source already there, out/ only"; }
  c "Free space at $(dirname "$SRC"): ${disk} GB (~$want GB needed – $what)"
  local swap
  swap=$(awk '/SwapTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
  c "Swap: ${swap} GB"
  if [ "$ram" -lt 24 ]; then
    warn "Little RAM. The build still works, but with fewer jobs than $(nproc) and correspondingly slow."
    [ $(( ram + swap )) -lt 32 ] && warn "RAM + swap below 32 GB – single compilers may get killed.
       Create a swap file:
         sudo fallocate -l 32G /swapfile && sudo chmod 600 /swapfile
         sudo mkswap /swapfile && sudo swapon /swapfile"
  fi
  if [ "$disk" -lt "$min" ]; then
    warn "Not enough space: ${disk} GB free, about $want GB needed ($what).
       This only fails after hours. What uses the most:
         du -xh --max-depth=1 \$HOME | sort -rh | head"
  fi
  if ! git config --global user.name >/dev/null 2>&1 \
     || ! git config --global user.email >/dev/null 2>&1; then
    warn "Git identity missing - repo stops during sync without it:
         git config --global user.name \"YOUR-NAME\"
         git config --global user.email \"YOUR-NAME@users.noreply.github.com\""
  fi
  for t in git git-lfs python3 curl zip unzip openssl fastboot adb simg2img fsck.erofs; do
    command -v "$t" >/dev/null && echo "  ✓ $t" || echo "  ✗ $t"
  done
  command -v repo >/dev/null && echo "  ✓ repo" || echo "  ✗ repo  →  curl -o ~/.local/bin/repo https://storage.googleapis.com/git-repo-downloads/repo && chmod +x ~/.local/bin/repo"
  cat <<'EOF'

Packages:
  Gentoo:  emerge -av dev-vcs/git dev-vcs/git-lfs app-arch/zip app-arch/unzip \
           sys-fs/erofs-utils sys-fs/e2fsprogs \
           dev-lang/python sys-devel/bc sys-devel/bison sys-devel/flex dev-libs/openssl \
           app-arch/lz4 dev-util/android-tools sys-libs/ncurses media-gfx/imagemagick
  Ubuntu:  sudo apt install erofs-utils bc bison build-essential curl flex g++-multilib gcc-multilib git \
           git-lfs gnupg gperf imagemagick lib32readline-dev lib32z1-dev libelf-dev liblz4-tool \
           lz4 libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool \
           squashfs-tools xsltproc zip zlib1g-dev python3 android-sdk-libsparse-utils
EOF
}

# ------------------------------------------------------------ sync
# Check the space where the build really happens. An Android build runs for
# hours to days; if the disk fills up during it, all that time is lost.
# Better stop here. Point NOXIS_SRC to another disk if the system disk is
# too small.
need_space() {  # $1 = path, $2 = GB needed, $3 = what for
  local free
  mkdir -p "$1" 2>/dev/null || true
  free=$(df -BG --output=avail "$1" 2>/dev/null | tail -1 | tr -dc 0-9)
  [ -n "$free" ] || return 0
  if [ "$free" -lt "$2" ]; then
    die "Not enough space for $3: $free GB free at $1, about $2 GB needed.
       Use another disk:     export NOXIS_SRC=/path/to/disk/noxis-src
       See what uses space:  du -xh --max-depth=1 \$HOME | sort -rh | head
       Skip this check:      NOXIS_SKIP_SPACE=1 (at your own risk)"
  fi
  c "Space at $1: $free GB free"
}

# repo creates its own commits in the manifest tree and needs a global
# identity for that. Without it, it only fails after initialising - so ask
# up front.
git_identity() {
  git config --global user.name >/dev/null 2>&1 \
    && git config --global user.email >/dev/null 2>&1 && return 0
  die "Git does not know you yet - repo needs that. Set it once:
         git config --global user.name \"YOUR-NAME\"
         git config --global user.email \"YOUR-NAME@users.noreply.github.com\"
       GitHub's noreply address keeps your real e-mail out of the commits."
}

cmd_sync() {
  need repo "see ./noxis.sh check"
  need git-lfs "install git-lfs – otherwise the WebView APKs and more are missing after the sync"
  git_identity
  [ "${NOXIS_SKIP_SPACE:-0}" = 1 ] || need_space "$(dirname "$SRC")" 150 "the source code"
  mkdir -p "$SRC" && cd "$SRC"
  if [ ! -d .repo ]; then
    c "Initialising LineageOS $BRANCH"
    repo init -u https://github.com/LineageOS/android.git -b "$BRANCH" --git-lfs --no-clone-bundle --depth=1
  fi
  mkdir -p .repo/local_manifests
  cp "$NOXIS/manifest/noxis.xml" .repo/local_manifests/noxis.xml
  c "Syncing the source (several hours the first time)"
  # --depth belongs to 'repo init', not 'repo sync' - there it is not a valid
  # option and fails immediately. The shallow depth is stored in the
  # manifest config since the init above and applies to every sync.
  #
  # Limit parallel fetches by RAM: each one is its own git process, and on a
  # machine with little memory the OOM killer takes some out mid-fetch.
  local jobs
  jobs=$(awk '/MemTotal/ {j=int($2/1024/1024/2); print (j<2 ? 2 : (j>8 ? 8 : j))}' /proc/meminfo)
  [ "$jobs" -gt "$(nproc)" ] && jobs=$(nproc)
  c "  $jobs parallel fetches"
  repo sync -c -j"$jobs" --force-sync --no-clone-bundle --no-tags --optimized-fetch --prune \
    || repo sync -c -j2 --force-sync --no-clone-bundle --no-tags
  lfs_fetch
  cmd_vendor
}

cmd_vendor() {
  drop_old_apps
  c "Copying vendor/noxis into the source tree"
  mkdir -p "$SRC/vendor/noxis"
  find "$SRC/vendor/noxis" -mindepth 1 -maxdepth 1 ! -name prebuilt -exec rm -rf {} +
  cp -a "$NOXIS/vendor/noxis/." "$SRC/vendor/noxis/"
  c "Applying the Noxis patches"
  python3 "$NOXIS/tools/noxis_patch.py" "$SRC"
}

# ------------------------------------------------------------ apps
gh_latest_asset() {  # <owner/repo> <regex>  →  download URL
  local repo="$1" re="$2" tag
  tag=$(curl -fsSIL -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest" | sed 's,.*/tag/,,')
  [ -n "$tag" ] || return 1
  curl -fsSL "https://github.com/$repo/releases/expanded_assets/$tag" \
    | grep -oE "/$repo/releases/download/[^\"]+" | grep -E "$re" | head -1 | sed 's,^,https://github.com,'
}

gh_tag_asset() {  # <owner/repo> <tag> <regex>  →  download URL of a fixed release
  curl -fsSL "https://github.com/$1/releases/expanded_assets/$2" \
    | grep -oE "/$1/releases/download/[^\"]+" | grep -E "$3" | head -1 | sed 's,^,https://github.com,'
}

tor_url() {  # newest stable Tor Browser for arm64
  local ver
  ver=$(curl -fsSL --max-time 60 https://dist.torproject.org/torbrowser/ | grep -oE 'href="[0-9]+\.[0-9]+(\.[0-9]+)?/"' \
        | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | sort -V | tail -1) || true
  [ -n "$ver" ] && echo "https://dist.torproject.org/torbrowser/$ver/tor-browser-android-aarch64-$ver.apk"
  return 0
}

fdroid_apk() {  # <package> → URL of F-Droid's suggested APK (main repo)
  local api code
  api=$(curl -fsSL --max-time 60 "https://f-droid.org/api/v1/packages/$1") || return 1
  code=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["suggestedVersionCode"])' "$api" 2>/dev/null) || return 1
  [ -n "$code" ] && echo "https://f-droid.org/repo/$1_$code.apk"
}

install_post() {  # <name> <url> – user app, installed via adb after flashing
  local name="$1" url="$2"
  [ -n "$url" ] || { warn "$name: no download address found – skipped"; return 0; }
  mkdir -p "$POST"
  c "$name ← $url"
  if curl -fL --progress-bar --connect-timeout 20 --max-time 1800 -o "$POST/$name.apk.part" "$url"; then
    mv "$POST/$name.apk.part" "$POST/$name.apk"
    c "  $name: installed after flashing (./noxis.sh postinstall)"
  else
    rm -f "$POST/$name.apk.part"; warn "$name: download failed – skipped"
  fi
  return 0
}

install_avdb() {
  local dir="$NOXIS/vendor/noxis/prebuilt/NoxisAvDb" f
  c "Virus signatures (ClamAV) for Noxis Guard"
  if ! python3 "$NOXIS/tools/noxis_avdb.py" "$dir"; then
    warn "ClamAV signatures not available – Noxis Guard only checks app behaviour"
    rm -rf "$dir"; return 0
  fi
  {
    for f in android_md5.idx android_sha1.idx android_sha256.idx android.names VERSION; do
      echo "prebuilt_etc {"
      echo "    name: \"noxis_av_$f\","
      echo "    src: \"$f\","
      echo "    filename: \"$f\","
      echo "    sub_dir: \"noxis/av\","
      echo "    product_specific: true,"
      echo "}"
    done
  } > "$dir/Android.bp"
}

# Root modules (KernelSU) of Noxis: zipped into postinstall/modules/, the
# phone gets them with ./noxis.sh postinstall.
build_ksu_modules() {
  local m name
  need zip "install zip"
  mkdir -p "$POST/modules"
  for m in "$NOXIS"/ksu-modules/*/; do
    [ -f "$m/module.prop" ] || continue
    name=$(basename "$m")
    rm -f "$POST/modules/$name.zip"
    ( cd "$m" && zip -qr9 "$POST/modules/$name.zip" . )
    c "KernelSU module $name → installed after flashing (./noxis.sh postinstall)"
  done
}

# IronFox: Firefox fork with uBlock Origin preinstalled and hardened defaults,
# signed by the IronFox project. Newest arm64 build from their F-Droid repo.
IRONFOX_REPO="https://fdroid.ironfoxoss.org/fdroid/repo"
install_ironfox() {
  local idx apk
  idx=$(curl -fsSL --max-time 120 "$IRONFOX_REPO/index-v1.json") \
    || { warn "IronFox: repo not reachable – skipped"; return 0; }
  apk=$(python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
p = [x for x in d["packages"].get("org.ironfoxoss.ironfox", []) if "arm64-v8a" in (x.get("nativecode") or [])]
print(max(p, key=lambda x: x["versionCode"])["apkName"] if p else "")' <<<"$idx" 2>/dev/null) || apk=""
  [ -n "$apk" ] || { warn "IronFox: no arm64 build in the repo – skipped"; return 0; }
  install_apk IronFox "$IRONFOX_REPO/$apk" false
}

install_apk() {  # <name> <url> <privileged:true|false>
  local name="$1" url="$2" priv="$3" dir
  dir="$NOXIS/vendor/noxis/prebuilt/$name"
  [ -n "$url" ] || { warn "$name: no download address found – skipped"; return 0; }
  mkdir -p "$dir"
  c "$name ← $url"
  # --max-time so a hanging server does not block the run forever.
  if ! curl -fL --progress-bar --connect-timeout 20 --max-time 1800 -o "$dir/$name.apk.part" "$url"; then
    warn "$name: download failed – skipped"
    rm -f "$dir/$name.apk.part"; rmdir "$dir" 2>/dev/null || true
    return 0
  fi
  mv "$dir/$name.apk.part" "$dir/$name.apk"
  install_apk_bp "$name" "$priv"
}

install_apk_bp() {  # <name> <privileged> – Android.bp for an already downloaded APK
  local name="$1" priv="$2" dir="$NOXIS/vendor/noxis/prebuilt/$1"
  cat > "$dir/Android.bp" <<EOF
android_app_import {
    name: "$name",
    apk: "$name.apk",
    presigned: true,
    // the v2/v3 signature only survives if Soong does not touch the APK
    preprocessed: true,
    product_specific: true,
    privileged: $priv,
    dex_preopt: {
        enabled: false,
    },
}
EOF
  if command -v apksigner >/dev/null; then
    apksigner verify --print-certs "$dir/$name.apk" | grep -m1 "SHA-256" | sed "s,^,    $name ,"
  fi
}

# KernelSU manager and kernel must speak the same interface version (UAPI),
# otherwise the app shows "Manager update required" / "Kernel update
# required". The kernel tree brings its own KernelSU copy, so read its UAPI
# version and take the newest official release with the same one.
ksu_kernel_uapi() {
  local h
  for h in $(grep -rls "KERNEL_SU_UAPI_VERSION *=" "$SRC"/kernel/nothing/sm7635/KernelSU "$SRC"/kernel/nothing/sm7635/drivers/kernelsu 2>/dev/null || true); do
    sed -n 's/.*KERNEL_SU_UAPI_VERSION *= *\([0-9]*\).*/\1/p' "$h" | head -1
    return 0
  done
  return 0
}

ksu_release_uapi() {  # <tag> → UAPI version of that release (empty if unknown)
  local p v
  for p in uapi/supercall.h kernel/uapi/supercall.h kernel/supercalls.h kernel/ksu.h; do
    v=$( { curl -fsSL --max-time 30 "https://raw.githubusercontent.com/tiann/KernelSU/$1/$p" 2>/dev/null || true; } \
         | sed -n 's/.*KERNEL_SU_UAPI_VERSION *= *\([0-9]*\).*/\1/p' | head -1)
    [ -n "$v" ] && { echo "$v"; return 0; }
  done
  return 0
}

ksu_tag() {
  [ -n "$KSU_TAG" ] && { echo "$KSU_TAG"; return 0; }
  [ "$KSU_PIN" != none ] && { echo "$KSU_PIN"; return 0; }
  local want tag have tags
  want=$(ksu_kernel_uapi)
  if [ -z "$want" ]; then
    warn "KernelSU UAPI version of the kernel not found – taking the newest manager"
    curl -fsSIL -o /dev/null -w '%{url_effective}' https://github.com/tiann/KernelSU/releases/latest | sed 's,.*/tag/,,'
    return 0
  fi
  c "KernelSU in the kernel: UAPI $want" >&2
  tags=$( { curl -fsSL --max-time 60 "https://api.github.com/repos/tiann/KernelSU/releases?per_page=15" || true; } \
          | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
  [ -n "$tags" ] || { warn "GitHub API not reachable"; return 0; }
  for tag in $tags; do
    have=$(ksu_release_uapi "$tag")
    c "  $tag: UAPI ${have:-?}" >&2
    if [ "$have" = "$want" ]; then
      c "KernelSU manager → $tag" >&2
      echo "$tag"; return 0
    fi
    # releases are newest first: once a release is older than the kernel,
    # no older one can match either
    if [ -n "$have" ] && [ "$have" -lt "$want" ]; then
      # The kernel carries a KernelSU that is newer than every release (from
      # the main branch). KernelSU's CI builds main with the official signing
      # key, so that manager is accepted by the kernel and speaks its UAPI.
      warn "The kernel's KernelSU is newer than the newest release – using the official main-branch build"
      echo "main"; return 0
    fi
  done
  warn "No KernelSU release with UAPI $want – set one with NOXIS_KSU_TAG=vX.Y.Z or NOXIS_KSU_TAG=main"
  return 0
}

# Download the KernelSU manager for a tag (or "main" = official CI build of
# the main branch, via nightly.link because GitHub artifacts need a login).
ksu_download() {  # <tag> <target.apk>
  local tag="$1" out="$2" url tmp
  if [ "$tag" = main ]; then
    tmp=$(mktemp -d)
    url="https://nightly.link/tiann/KernelSU/workflows/build-manager/main/manager-gradle.zip"
    c "KernelSU manager ← $url"
    curl -fL --progress-bar --max-time 900 -o "$tmp/m.zip" "$url" || { rm -rf "$tmp"; return 1; }
    unzip -q -o "$tmp/m.zip" -d "$tmp" && ls "$tmp"/*.apk >/dev/null 2>&1 || { rm -rf "$tmp"; return 1; }
    mv -f "$(ls "$tmp"/*.apk | head -1)" "$out"; rm -rf "$tmp"
  else
    url=$(gh_tag_asset tiann/KernelSU "$tag" 'KernelSU.*\.apk$' || true)
    [ -n "$url" ] || return 1
    c "KernelSU manager ← $url"
    curl -fL --progress-bar --max-time 900 -o "$out" "$url" || return 1
  fi
}

# Replace the kernel tree's KernelSU copy with the official release KSU_PIN.
# The source comes as a tarball (no .git), so KernelSU's Kbuild would fall
# back to version 16 - the version number is written in from the release's
# manager APK name (KernelSU_v3.3.1_32703-release.apk → 32703).
ksu_pin() {
  [ "$KSU_PIN" = none ] && return 0
  local dir="$SRC/kernel/nothing/sm7635/KernelSU" mark tmp ver
  [ -d "$dir" ] || { warn "KernelSU: $dir missing – kernel not synced?"; return 0; }
  mark="$dir/.noxis-pin"
  [ "$(cat "$mark" 2>/dev/null)" = "$KSU_PIN" ] && { c "KernelSU in the kernel: $KSU_PIN"; return 0; }
  ver=$(gh_tag_asset tiann/KernelSU "$KSU_PIN" 'KernelSU.*\.apk$' | sed -n 's/.*_\([0-9]\{5\}\)-release\.apk$/\1/p')
  [ -n "$ver" ] || die "KernelSU $KSU_PIN: version number not found (release missing?)"
  c "KernelSU in the kernel → official $KSU_PIN (version $ver)"
  tmp=$(mktemp -d)
  curl -fsSL --max-time 600 "https://github.com/tiann/KernelSU/archive/refs/tags/$KSU_PIN.tar.gz" \
    | tar -xz -C "$tmp" --strip-components=1 || { rm -rf "$tmp"; die "KernelSU $KSU_PIN: download failed"; }
  [ -f "$tmp/kernel/Kbuild" ] || { rm -rf "$tmp"; die "KernelSU $KSU_PIN: unexpected archive"; }
  sed -i "s/-DKSU_VERSION=16/-DKSU_VERSION=$ver/" "$tmp/kernel/Kbuild"
  grep -q "DKSU_VERSION=$ver" "$tmp/kernel/Kbuild" || { rm -rf "$tmp"; die "KernelSU: version line not found in Kbuild"; }
  find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  cp -a "$tmp/." "$dir/"
  echo "$KSU_PIN" > "$mark"
  rm -rf "$tmp"
}

# Only the KernelSU manager: download the matching one and, if the phone is
# connected with USB debugging, install it right away (updates the old one).
cmd_ksu() {
  need curl "install curl"; need unzip "install unzip"
  local tag
  tag=$(ksu_tag); [ -n "$tag" ] || die "no matching KernelSU manager"
  mkdir -p "$POST"
  ksu_download "$tag" "$POST/KernelSU.apk" || die "KernelSU $tag: download failed"
  if command -v adb >/dev/null && [ "$(adb get-state 2>/dev/null)" = device ]; then
    adb install -r "$POST/KernelSU.apk" && c "KernelSU manager ($tag) installed"
  else
    c "Phone not connected – later: ./noxis.sh postinstall"
  fi
}

# ------------------------------------------------------------ 3rr0r's own apps (built by GitHub Actions)
# name → LineageOS app it replaces (empty = added next to the stock app)
NOXIS_APPS_REPO="${NOXIS_APPS_REPO:-Real3rr0r303YT/NoxisOS}"
NOXIS_OWN_APPS="NoxisCalendar:Etar NoxisClock:DeskClock NoxisCalculator:ExactCalculator NoxisNotes: NoxisCall: NoxisBattery:"

install_own_apps() {
  local base="${NOXIS_APPS_URL:-https://github.com/$NOXIS_APPS_REPO/releases/download/noxis-apps}" tmp entry name over dir
  tmp=$(mktemp -d)
  if ! curl -fsSL -o "$tmp/SHA256SUMS" "$base/SHA256SUMS"; then
    warn "noxis-apps release not found ($NOXIS_APPS_REPO) – run the 'Noxis apps' GitHub Action first"
    rm -r "$tmp"; return 0
  fi
  curl -fsSL -o "$tmp/SOURCES" "$base/SOURCES" || : > "$tmp/SOURCES"
  for entry in $NOXIS_OWN_APPS; do
    name="${entry%%:*}"; over="${entry#*:}"
    grep -q " $name.apk\$" "$tmp/SHA256SUMS" || { warn "$name: not in the release – skipped"; continue; }
    c "$name ← $base/$name.apk"
    curl -fsSL -o "$tmp/$name.apk" "$base/$name.apk" || { warn "$name: download failed – skipped"; continue; }
    if ! ( cd "$tmp" && grep " $name.apk\$" SHA256SUMS | sha256sum -c --quiet - ); then
      warn "$name: SHA-256 MISMATCH – skipped"; continue
    fi
    dir="$NOXIS/vendor/noxis/prebuilt/$name"; mkdir -p "$dir"
    mv "$tmp/$name.apk" "$dir/$name.apk"
    grep "^$name " "$tmp/SOURCES" > "$dir/SOURCE" || true
    {
      echo "android_app_import {"
      echo "    name: \"$name\","
      echo "    apk: \"$name.apk\","
      echo "    // test key while building, replaced by the Noxis key when signing (noxis.sh sign)"
      echo "    default_dev_cert: true,"
      echo "    product_specific: true,"
      [ -n "$over" ] && echo "    overrides: [\"$over\"],"
      echo "    dex_preopt: {"
      echo "        enabled: false,"
      echo "    },"
      echo "}"
    } > "$dir/Android.bp"
    c "  $name ok${over:+ (replaces $over)} – $(cut -d' ' -f2- "$dir/SOURCE" 2>/dev/null)"
  done
  rm -r "$tmp"
}

# Apps that Noxis no longer ships: remove leftovers of earlier runs, otherwise
# the old prebuilt in the source tree (cmd_vendor keeps prebuilt/) would still
# end up in the image.
NOXIS_DROPPED_APPS="Cromite NoxisLauncher Fennec NoxisPacker"
drop_old_apps() {
  local n
  for n in $NOXIS_DROPPED_APPS; do
    if [ -e "$NOXIS/vendor/noxis/prebuilt/$n" ] || [ -e "$SRC/vendor/noxis/prebuilt/$n" ] || [ -e "$POST/$n.apk" ]; then
      c "$n: no longer part of Noxis – removed"
    fi
    rm -rf "$NOXIS/vendor/noxis/prebuilt/$n" "$SRC/vendor/noxis/prebuilt/$n" "$POST/$n.apk"
  done
}

cmd_apps() {
  need curl "install curl"
  drop_old_apps
  install_own_apps
  install_apk GrapheneCamera    "$(gh_latest_asset GrapheneOS/Camera '\.apk$' || true)" false
  install_apk GraphenePdfViewer "$(gh_latest_asset GrapheneOS/PdfViewer '\.apk$' || true)" false
  # Default browser: IronFox (hardened Firefox, uBlock Origin preinstalled)
  install_ironfox
  # App stores without Google: F-Droid (open source) and Aurora Store
  # (Play Store apps anonymously, no Google account). Both into the image.
  install_apk FDroid      "$(fdroid_apk org.fdroid.fdroid || true)" false
  install_apk AuroraStore "$(fdroid_apk com.aurora.store || true)" false
  # Termux: user app (own data dir, updates via F-Droid) → installed after flashing
  install_post Termux "$(fdroid_apk com.termux || true)"
  install_apk MullvadVPN        "https://mullvad.net/download/app/apk/latest" false
  install_apk TorBrowser        "$(tor_url)" false
  # Virus signatures for Noxis Guard (ClamAV, Android malware only)
  install_avdb
  # KernelSU modules from ksu-modules/ → installed after flashing
  build_ksu_modules
  # The manager has to match the KernelSU in the kernel and be officially signed
  local kt; kt=$(ksu_tag)
  if [ "$kt" = main ]; then
    # CI build: download, then register it like the other prebuilts
    mkdir -p "$NOXIS/vendor/noxis/prebuilt/KernelSU"
    if ksu_download main "$NOXIS/vendor/noxis/prebuilt/KernelSU/KernelSU.apk"; then
      install_apk_bp KernelSU false
    else
      warn "KernelSU manager: download failed – skipped"
    fi
  else
    install_apk KernelSU "$(gh_tag_asset tiann/KernelSU "$kt" 'KernelSU.*\.apk$' || true)" false
  fi
  [ -d "$SRC/vendor" ] && cmd_vendor
  return 0
}

# ------------------------------------------------------------ blobs
cmd_blobs() {
  local ota="${1:-}"
  [ -f "$ota" ] || [ -d "$ota" ] || die "Give the path to the Nothing OS OTA (full .zip) or to a dump"
  # The Nothing OS partitions are EROFS. Without fsck.erofs extract-files.py
  # extracts nothing at all but only warns and continues - you end up with a
  # thousand "file not found" lines and the real cause far up in the log.
  command -v fsck.erofs >/dev/null 2>&1 \
    || die "fsck.erofs is missing - without it no partition can be opened.
       Gentoo:  sudo emerge -av sys-fs/erofs-utils
       Ubuntu:  sudo apt install erofs-utils"
  ota="$(cd "$(dirname "$ota")" && pwd)/$(basename "$ota")"
  local want
  want=$(sed -n 's/^## .*are from the \(.*\) release.*/\1/p' "$SRC/device/nothing/$DEVICE/proprietary-files.txt" | head -1)
  [ -n "$want" ] && c "Device tree expects Nothing OS: $want"
  # Compare the dump's version with the expected one before anything
  # happens. A different version does not cause one error but many:
  # different checksums, missing and new dependencies, and each only shows
  # up during the build. That once cost an hour - so stop here.
  if [ -n "$want" ] && [ -d "$ota" ] && [ "$NOXIS_OTHER_FIRMWARE" != 1 ]; then
    local prop have=""
    for prop in "$ota/system/build.prop" "$ota/system/system/build.prop" \
                "$ota/vendor/build.prop" "$ota/product/etc/build.prop"; do
      [ -f "$prop" ] || continue
      have=$(grep -m1 -E '^ro\.(build\.display\.id|system\.build\.version\.incremental|vendor\.build\.version\.incremental)=' "$prop" | cut -d= -f2-)
      [ -n "$have" ] && break
    done
    if [ -n "$have" ] && ! printf '%s' "$have" | grep -qF "$want"; then
      die "The dump is a different Nothing OS version:
         dump:      $have
         expected:  $want
       Checksums and dependencies will not match and the build fails at
       ever new places. The matching version is here
       (Phone (3a) -> $want -> 'OTA Images'):
         https://nothingarchive.tech/docs/firmware
       Continue anyway on purpose:  NOXIS_OTHER_FIRMWARE=1 ./noxis.sh blobs ..."
    elif [ -n "$have" ]; then
      c "Dump matches: $have"
    fi
  fi
  cd "$SRC/device/nothing/$DEVICE"
  # The device tree hard-codes file names and checksums of one specific
  # Nothing OS version. If your dump is a different one, both do not match:
  # checksums differ, and region-specific files (Verizon in US firmware) are
  # missing completely. With --regen extract-files.py rewrites the list from
  # the dump you have.
  local regen=""
  case "${2:-}${NOXIS_REGEN:+--regen}" in *--regen*|*--neu*) regen="--regenerate" ;; esac
  if [ -n "$regen" ]; then
    c "Extracting vendor files, rewriting the file list (different Nothing OS version)"
    warn "proprietary-files.txt gets rewritten. Rename entries (source:target)
       can get lost, and the build then reports 'depends on undefined
       module'. Reset it with:
         cd $SRC/device/nothing/$DEVICE && git checkout proprietary-files.txt
       Missing Verizon/Miracast files do not need --regen, tools/blobs-skip.txt
       removes them anyway."
  else
    c "Extracting vendor files (Wi-Fi, mobile/IMS, NFC, eSIM, camera, firmware)"
  fi
  # Noxis patches first: some of them touch the file list and
  # extract-files.py itself (e.g. the camera library postproc@1.0-nt). They
  # are repeatable and therefore also apply after a 'git checkout' of the list.
  c "Applying the Noxis patches to the device tree"
  python3 "$NOXIS/tools/noxis_patch.py" "$SRC" || die "Noxis patches failed"
  # What Noxis leaves out on purpose comes off the list before every
  # extraction - also after a 'repo sync' resets proprietary-files.txt.
  c "Removing skipped vendor files from the list"
  { grep -v '^[[:space:]]*\(#\|$\)' "$NOXIS/tools/blobs-skip.txt" || true; } \
    | python3 "$NOXIS/tools/noxis_blobs_clean.py" "$SRC/device/nothing/$DEVICE/proprietary-files.txt" \
    || die "The list of skipped files could not be applied"
  # The other way round: what newer Nothing OS versions need in addition.
  # Only added if the file exists in the extracted dump - otherwise the
  # extraction would fail on an entry without a file.
  local list_pf="$SRC/device/nothing/$DEVICE/proprietary-files.txt" extra
  if [ -d "$ota" ] && [ -f "$NOXIS/tools/blobs-add.txt" ]; then
    # '|| true': without entries grep returns 1, and with pipefail the
    # script would end here silently - exactly how the extraction once failed.
    { grep -v '^[[:space:]]*\(#\|$\)' "$NOXIS/tools/blobs-add.txt" || true; } | while read -r extra; do
      grep -qF "$extra" "$list_pf" && continue
      if [ -e "$ota/$extra" ]; then
        printf '%s\n' "$extra" >> "$list_pf"
        c "  added: $extra"
      else
        c "  not in the dump, stays out: $extra"
      fi
    done
  fi
  if [ -z "$regen" ]; then
    ./extract-files.py "$ota"
  else
    # extract-files.py itself says which files it cannot find
    # ("<path>: file not found") and then stops. Exactly those entries are
    # taken off the list and it tries again. That way it depends on what the
    # tool finds, not on an assumption about how the dump is laid out.
    # The exit code is no help: extract-files.py ends with 0 even when it
    # writes "Some files failed to process, exiting". So the output decides.
    local log list try=0 missing
    log=$(mktemp); list="$SRC/device/nothing/$DEVICE/proprietary-files.txt"
    while [ "$try" -le 3 ]; do
      ./extract-files.py --regenerate "$ota" 2>&1 | tee "$log" || true
      # Strip colour codes and carriage returns first: extract-files.py
      # colours error lines, and then a pattern with '^' and '$' fails.
      missing=$(sed 's/\x1b\[[0-9;]*[A-Za-z]//g; s/\r$//' "$log" \
                | sed -n 's/^[[:space:]]*\(.*[^[:space:]]\):[[:space:]]*file not found[[:space:]]*$/\1/p' \
                | sort -u)
      if [ -z "$missing" ]; then
        # Stopped, but nothing recognised: show what the lines really look
        # like instead of giving up silently.
        if grep -q "failed to process" "$log"; then
          warn "Extraction stopped, but no 'file not found' line was recognised. They look like this:"
          grep -a "file not found" "$log" | head -3 | cat -v | sed 's/^/       /'
        fi
        break
      fi
      try=$((try + 1))
      c "Removing entries without a file in the dump (pass $try)"
      if ! printf '%s\n' "$missing" | python3 "$NOXIS/tools/noxis_blobs_clean.py" "$list"; then
        rm -f "$log"; die "Clean-up failed"
      fi
    done
    rm -f "$log"
  fi
  [ -f "$SRC/vendor/nothing/$DEVICE/$DEVICE-vendor.mk" ] || die "Extraction incomplete"
  c "OK: vendor/nothing/$DEVICE"
}

# ------------------------------------------------------------ keys
make_key4096() {  # <path-without-extension> <subject>
  local tmp
  tmp=$(mktemp -d)
  cp "$SRC/development/tools/make_key" "$tmp/make_key"
  sed -i 's|2048|4096|g' "$tmp/make_key"
  printf '\n' | "$tmp/make_key" "$1" "$2" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}

cmd_keys() {
  [ -x "$SRC/development/tools/make_key" ] || die "Run ./noxis.sh sync first"
  mkdir -p "$KEYS" && chmod 700 "$KEYS"
  for cert in releasekey platform shared media networkstack sdk_sandbox bluetooth nfc testkey; do
    [ -f "$KEYS/$cert.pk8" ] && continue
    c "Key: $cert"
    printf '\n' | "$SRC/development/tools/make_key" "$KEYS/$cert" "$SUBJECT" >/dev/null 2>&1 || true
    [ -f "$KEYS/$cert.pk8" ] || die "make_key $cert failed"
  done
  if [ ! -f "$KEYS/avb.pem" ]; then
    c "Verified boot key (RSA-4096)"
    openssl genrsa -out "$KEYS/avb.pem" 4096 2>/dev/null
  fi
  chmod 600 "$KEYS"/*
  c "Keys are in $KEYS"
  warn "BACK THEM UP! Without these keys no Noxis OTA update can be installed any more (only a reinstall with data loss)."
}

apex_keys() {  # <target_files.zip>
  local base
  python3 "$NOXIS/tools/noxis_sign_args.py" "$1" "$KEYS" apexes | while read -r base; do
    [ -f "$KEYS/$base.pem" ] && continue
    make_key4096 "$KEYS/$base" "/C=DE/O=Noxis OS/CN=$base"
    openssl pkcs8 -in "$KEYS/$base.pk8" -inform DER -nocrypt -out "$KEYS/$base.pem"
  done
}

# ------------------------------------------------------------ build
cmd_build() {
  [ -f "$SRC/vendor/nothing/$DEVICE/$DEVICE-vendor.mk" ] || die "Run ./noxis.sh blobs <ota.zip> first"
  # out/ grows to more than 100 GB while building.
  # What out/ already uses is subtracted from the need - otherwise every
  # resumed build after an abort would fail at the space check.
  local have=0 needed
  [ -d "$SRC/out" ] && have=$(du -sBG "$SRC/out" 2>/dev/null | cut -f1 | tr -dc 0-9 || echo 0)
  needed=$(( 130 - ${have:-0} )); [ "$needed" -lt 15 ] && needed=15
  [ "${NOXIS_SKIP_SPACE:-0}" = 1 ] || need_space "$SRC" "$needed" "out/ (still to build, ${have:-0} GB already there)"
  cmd_vendor
  c "Checking privileged permissions"
  python3 "$NOXIS/tools/noxis_privapp_check.py" "$SRC" "$SRC/vendor/noxis" \
    || die "A permission is missing in vendor/noxis/permissions – that would be a boot loop (see above)"
  if [ "$NOXIS_DEBUG" = 1 ]; then
    echo "NOXIS_DEBUG := 1" > "$SRC/vendor/noxis/config/noxis_debug.mk"
    warn "DEBUG BUILD ($VARIANT): ADB open without approval – for debugging only!"
  else
    rm -f "$SRC/vendor/noxis/config/noxis_debug.mk"
  fi
  apks_check
  lfs_check
  ksu_pin
  zram_on
  envsetup
  # ccache is off: on the first build the cache is empty and does not help,
  # and inside the Android 17 build sandboxes it fails with "ccache: error:
  # Not a directory". If you want it for later rebuilds: NOXIS_CCACHE=1.
  if [ "${NOXIS_CCACHE:-0}" = 1 ] && command -v ccache >/dev/null; then
    mkdir -p "$HOME/.ccache-noxis"
    export USE_CCACHE=1 CCACHE_EXEC="$(command -v ccache)" CCACHE_DIR="$HOME/.ccache-noxis"
    ccache -M "${NOXIS_CCACHE_SIZE:-25G}" >/dev/null
  else
    unset USE_CCACHE CCACHE_EXEC
  fi
  # Without a limit mka starts as many compilers as there are cores. Each
  # needs memory; on a machine with little RAM that ends in the OOM killer,
  # usually after hours. So: one job per 4 GB.
  #
  # Swap counts, but only half. Not every compiler needs its memory at the
  # same time, so some may be swapped out - counted fully the machine would
  # only swap instead of compile. With 14 GB RAM and 24 GB swap that gives
  # 6 instead of 3 jobs and roughly half the build time.
  local ram swap jobs
  ram=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
  swap=$(awk '/SwapTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
  jobs="${NOXIS_JOBS:-$(( (ram + swap / 2) / 4 ))}"
  [ "$jobs" -lt 2 ] && jobs=2
  [ "$jobs" -gt "$(nproc)" ] && jobs=$(nproc)
  c "Building Noxis OS ($DEVICE-$VARIANT) with $jobs jobs (${ram} GB RAM + ${swap} GB swap) – this takes a while"
  if [ "$ram" -lt 24 ]; then
    warn "Little RAM: expect many hours.
       If the PC only swaps (disk busy all the time, no progress), restart
       with fewer jobs: NOXIS_JOBS=$(( jobs - 2 ))
       More jobs work too: NOXIS_JOBS=n"
  fi
  # Time left: printed every 5 minutes (stops by itself when the build ends).
  # In a second terminal at any time: ./noxis.sh eta
  rm -f "$SRC/out/build_progress.pb"
  python3 "$NOXIS/tools/noxis_eta.py" "$SRC/out" --every "${NOXIS_ETA_EVERY:-300}" --pid $$ &
  local eta=$!
  if ! mka -j"$jobs" target-files-package otatools; then
    kill "$eta" 2>/dev/null || true
    die "Build failed – look for the first line with 'error:' in the log above"
  fi
  kill "$eta" 2>/dev/null || true
  c "Build done."
  cmd_opsec || die "OPSEC check failed – see above"
  c "Next: ./noxis.sh sign"
}

# ------------------------------------------------------------ opsec
# Checks the built image against the Noxis rules. The device trees come from
# other projects and change; whatever slips in should show up here and not
# only on the phone.
cmd_opsec() {
  local prod="$SRC/out/target/product/$DEVICE"
  [ -d "$prod" ] || die "Nothing built – run ./noxis.sh build first"
  NOXIS_POSTINSTALL="$POST" "$NOXIS/tools/opsec-verify.sh" "$prod"
}

# ------------------------------------------------------------ sign
cmd_sign() {
  [ -f "$KEYS/releasekey.pk8" ] || die "Run ./noxis.sh keys first"
  envsetup
  local tf
  local pout="${ANDROID_PRODUCT_OUT:-$SRC/out/target/product/$DEVICE}"
  tf=$(ls -t "$pout"/obj/PACKAGING/target_files_intermediates/*-target_files*.zip 2>/dev/null | head -1 || true)
  [ -f "$tf" ] || die "No target_files.zip – run ./noxis.sh build first"
  c "Creating APEX keys"
  apex_keys "$tf"
  mkdir -p "$REL"
  local stamp; stamp=$(date -u +%Y%m%d)
  local name="Noxis-1.0-$stamp-$DEVICE"
  local -a args
  mapfile -t args < <(python3 "$NOXIS/tools/noxis_sign_args.py" "$tf" "$KEYS" args)
  c "Signing (apps, APEXes, verified boot)"
  sign_target_files_apks "${args[@]}" "$tf" "$REL/$name-target_files.zip"
  c "OTA package"
  ota_from_target_files -k "$KEYS/releasekey" "$REL/$name-target_files.zip" "$REL/$name-ota.zip"
  c "Fastboot images"
  img_from_target_files "$REL/$name-target_files.zip" "$REL/$name-img.zip"
  ( cd "$REL" && sha256sum "$name-ota.zip" "$name-img.zip" > "$name.sha256" )
  write_ota_json "$REL/$name-ota.zip" "noxis-$stamp" > "$REL/$DEVICE.json"
  c "Done in $REL:"
  ls -1 "$REL" | sed 's,^,  ,'
  cmd_cleanup
}

# ------------------------------------------------------------ OTA updates over GitHub
NOXIS_GH_REPO="${NOXIS_GH_REPO:-Real3rr0r303YT/NoxisOS}"

ota_timestamp() {  # build time of the OTA (the Updater only offers builds newer than the installed one)
  local ts
  ts=$(unzip -p "$1" META-INF/com/android/metadata 2>/dev/null | sed -n 's/^post-timestamp=//p' | head -n1)
  [ -n "$ts" ] || ts=$(date -u -r "$1" +%s)
  echo "$ts"
}

write_ota_json() {  # <ota.zip> <release tag>  → LineageOS Updater JSON on stdout
  local ota="$1" tag="$2" file size id
  file=$(basename "$ota"); size=$(stat -c %s "$ota"); id=$(sha256sum "$ota" | cut -d' ' -f1)
  cat <<EOF
{
  "response": [
    {
      "datetime": $(ota_timestamp "$ota"),
      "filename": "$file",
      "id": "$id",
      "romtype": "UNOFFICIAL",
      "size": $size,
      "url": "https://github.com/$NOXIS_GH_REPO/releases/download/$tag/$file",
      "version": "24.0"
    }
  ]
}
EOF
}

release_notes() {  # <img.zip name>
  cat <<EOF
Noxis OS for the Nothing Phone (3a) (asteroids) – signed with the Noxis release keys.

**Update an existing Noxis:** Settings → System → Updater.

**Fresh install** (bootloader unlocked, Nothing OS firmware on the phone):
\`\`\`bash
# 1. put the image zip back together (skip if there is a single $1)
cat $1.part* > $1
# 2. flash everything (boot/vbmeta to both slots, system via fastbootd – wipes data)
git clone https://github.com/Real3rr0r303YT/NoxisOS && cd NoxisOS
mkdir -p release && mv ../$1 release/ && ./noxis.sh flash
\`\`\`
Small images by hand: \`fastboot flash boot_a boot.img\` (same for _b, init_boot, vendor_boot, recovery, dtbo) and \`fastboot --disable-verity --disable-verification flash vbmeta_a vbmeta.img\`.

Checksums: SHA256SUMS. Made by 3rr0r303YT on TikTok – GPL-3.0.
EOF
}

cmd_publish() {  # newest signed OTA → GitHub release + ota/<device>.json (read by the phone's Updater)
  need gh "install the GitHub CLI and run 'gh auth login'"
  need unzip "install unzip"
  local ota desk tag json
  desk="$(desktop_dir)"
  ota=$(ls -t "$desk"/Noxis-*-"$DEVICE"-ota.zip "$REL"/Noxis-*-"$DEVICE"-ota.zip 2>/dev/null | head -n1 || true)
  [ -f "$ota" ] || die "No signed OTA found – run ./noxis.sh sign first"
  [ "$(stat -c %s "$ota")" -lt 2147483648 ] || die "OTA larger than 2 GiB – GitHub releases allow at most 2 GiB per file"
  unzip -tq "$ota" >/dev/null || die "OTA zip damaged: $ota"
  unzip -l "$ota" | grep -q "META-INF/com/android/otacert" || die "OTA without signing certificate – create it with ./noxis.sh sign"
  tag="noxis-$(basename "$ota" | sed -n 's/^Noxis-[0-9.]*-\([0-9]\{8\}\)-.*/\1/p')"
  [ "$tag" != noxis- ] || tag="noxis-$(date -u +%Y%m%d)"
  ( cd "$(dirname "$ota")" && sha256sum "$(basename "$ota")" ) > "$ota.sha256"
  # Same OTA already released (e.g. an earlier publish broke off)? Then
  # complete that release instead of making a second one.
  local update=0
  if gh release view "$tag" -R "$NOXIS_GH_REPO" >/dev/null 2>&1; then
    if [ "$(gh release download "$tag" -R "$NOXIS_GH_REPO" -p "$(basename "$ota").sha256" -O - 2>/dev/null | cut -d' ' -f1)" \
         = "$(cut -d' ' -f1 "$ota.sha256")" ]; then
      update=1
    else
      tag="$tag-$(date -u +%H%M)"
    fi
  fi
  local files=("$ota" "$ota.sha256") img stage name part f
  # Fastboot images of the same build: the small ones (boot, recovery,
  # vbmeta …) one by one, the whole img.zip in parts below GitHub's 2 GiB
  # limit (put back together with cat).
  img="${ota%-ota.zip}-img.zip"
  [ -f "$img" ] || img="$REL/$(basename "${ota%-ota.zip}")-img.zip"
  stage=$(mktemp -d)
  if [ -f "$img" ]; then
    unzip -tq "$img" >/dev/null || die "img.zip damaged: $img"
    for name in boot init_boot vendor_boot recovery dtbo vbmeta vbmeta_system vbmeta_vendor; do
      unzip -l "$img" "$name.img" >/dev/null 2>&1 || continue
      unzip -oq "$img" "$name.img" -d "$stage"
      files+=("$stage/$name.img")
    done
    if [ "$(stat -c %s "$img")" -lt 2000000000 ]; then
      files+=("$img")
    else
      split -b 1900M -d -a 1 "$img" "$stage/$(basename "$img").part"
      for part in "$stage/$(basename "$img")".part*; do files+=("$part"); done
    fi
    for f in "${files[@]}"; do
      [ "${f%.sha256}" = "$f" ] || continue
      ( cd "$(dirname "$f")" && sha256sum "$(basename "$f")" )
    done > "$stage/SHA256SUMS"
    files+=("$stage/SHA256SUMS")
  else
    warn "No img.zip next to the OTA – only the OTA is uploaded"
  fi
  c "Release $tag ← $(basename "$ota") ($(du -h "$ota" | cut -f1)) + $(( ${#files[@]} - 1 )) more files"
  if [ "$update" = 1 ]; then
    c "Release $tag already has this OTA – adding the missing files"
    local missing=() have
    have=$(gh release view "$tag" -R "$NOXIS_GH_REPO" --json assets -q '.assets[].name' 2>/dev/null || true)
    for f in "${files[@]}"; do
      [ "$(basename "$f")" = SHA256SUMS ] || ! grep -qxF "$(basename "$f")" <<<"$have" || continue
      missing+=("$f")
    done
    [ ${#missing[@]} = 0 ] || gh release upload "$tag" "${missing[@]}" -R "$NOXIS_GH_REPO" --clobber
    gh release edit "$tag" -R "$NOXIS_GH_REPO" --notes "$(release_notes "$(basename "$img")")" >/dev/null
  else
    gh release create "$tag" "${files[@]}" -R "$NOXIS_GH_REPO" \
      --title "Noxis OS ${tag#noxis-}" \
      --notes "$(release_notes "$(basename "$img")")"
  fi
  rm -rf -- "$stage"
  mkdir -p "$NOXIS/ota"
  json="$NOXIS/ota/$DEVICE.json"
  write_ota_json "$ota" "$tag" > "$json"
  git -C "$NOXIS" add "ota/$DEVICE.json"
  git -C "$NOXIS" diff --cached --quiet || git -C "$NOXIS" commit -qm "OTA: $(basename "$ota")"
  # GitHub may have newer commits (app builds, script updates) – put ours on top
  git -C "$NOXIS" pull -q --rebase origin main || die "git pull failed – run 'git status' in $NOXIS"
  git -C "$NOXIS" push -q origin HEAD:main
  c "Published. Phone: Settings → System → Updater → Check for updates"
}

# ------------------------------------------------------------ cleanup
desktop_dir() {
  local d=""
  command -v xdg-user-dir >/dev/null && d=$(xdg-user-dir DESKTOP 2>/dev/null || true)
  [ -n "$d" ] && [ "$d" != "$HOME" ] || d="$HOME/Desktop"
  echo "$d"
}

cmd_cleanup() {
  local ota img desk
  ota=$(latest ota.zip); img=$(latest img.zip)
  [ -f "$ota" ] && [ -f "$img" ] || die "No finished ROM in $REL – out/ is NOT deleted"
  desk=$(desktop_dir); mkdir -p "$desk"
  c "ROM → $desk"
  local f
  for f in "$ota" "$img"; do
    [ "$(dirname "$f")" = "$desk" ] || cp -f "$f" "$desk/"
  done
  for f in "$ota" "$img"; do
    [ "$(sha256sum < "$f")" = "$(sha256sum < "$desk/$(basename "$f")")" ] \
      || die "Copy of $(basename "$f") is broken – out/ is NOT deleted"
  done
  # out/ is kept by default (next build: minutes instead of hours).
  # NOXIS_KEEP_OUT=0 frees the space.
  if [ "${NOXIS_KEEP_OUT:-1}" != "0" ]; then
    c "out/ is kept for fast rebuilds ($(du -sh "$SRC/out" 2>/dev/null | cut -f1)) – NOXIS_KEEP_OUT=0 ./noxis.sh cleanup deletes it"
    return 0
  fi
  local o="$SRC/out"
  [ -n "$SRC" ] && [ "$o" = "$SRC/out" ] || die "Unexpected out path: $o"
  [ -d "$o" ] && [ -f "$SRC/build/envsetup.sh" ] || { c "out/ not present"; return 0; }
  c "Deleting $o ($(du -sh "$o" 2>/dev/null | cut -f1))"
  rm -rf -- "$o"
  # the signed target_files is only needed for delta OTAs – save space
  rm -f -- "$REL"/Noxis-*-target_files.zip
  c "Now used: $(du -sh "$SRC" 2>/dev/null | cut -f1) source"
}

# ------------------------------------------------------------ flash
latest() { ls -t "$REL"/Noxis-*-"$1" "$(desktop_dir)"/Noxis-*-"$1" 2>/dev/null | head -1 || true; }

# Flash one image. vbmeta with verification switched off: with verification
# init aborts during boot and the phone drops back to the bootloader (cause
# still open, see README "Known issues").
flash_part() {  # <partition> <image>
  local -a fl=()
  case "$1" in vbmeta|vbmeta_a|vbmeta_b) fl=(--disable-verity --disable-verification) ;; esac
  fastboot "${fl[@]}" flash "$1" "$2"
}

# Wait until the phone is in fastbootd (userspace fastboot in the recovery).
# Right after "fastboot reboot fastboot" the bootloader may still answer for
# a moment, so ask for is-userspace instead of just looking for a device.
wait_fastbootd() {
  local i
  sleep 3
  for i in $(seq 1 90); do
    fastboot getvar is-userspace 2>&1 | grep -q "is-userspace: yes" && return 0
    sleep 1
  done
  return 1
}

# Flashing writes everything directly with fastboot - no OTA via adb sideload.
# Reason: on this phone an OTA from the recovery goes into the other slot as a
# "virtual A/B" snapshot. If that slot never boots successfully, the bootloader
# switches back to the old slot after a few tries, and "Format data" deletes
# the snapshot. Written directly, slot a is complete and stays that way.
cmd_flash() {
  need fastboot "install android-tools"
  local img
  img=$(latest img.zip)
  [ -f "$img" ] || die "Run ./noxis.sh sign first"
  c "ROM: $(basename "$img")"
  cat <<EOF

  Preparation (once):
   1. Do NOT update Nothing OS – the firmware should match the version the
      blobs came from (./noxis.sh blobs).
   2. Settings → About phone → tap "Build number" 7× → Developer options
      → turn on "OEM unlocking" + "USB debugging".
   3. Back up everything important – the phone gets wiped completely.
   4. adb reboot bootloader  →  fastboot flashing unlock  → confirm with the volume keys

EOF
  confirm "Is the phone unlocked and connected in fastboot mode?" || exit 0
  local prod; prod=$(fastboot getvar product 2>&1 | sed -n 's/^product: *//p')
  # In the bootloader the Phone (3a) reports the Qualcomm platform name
  # "pineapple" instead of "asteroids" - both are correct.
  case "${prod,,}" in
    *asteroids*|pineapple) c "Device: $prod (Nothing Phone (3a))" ;;
    *) confirm "Device reports '$prod' instead of asteroids/pineapple. Continue anyway?" || exit 1 ;;
  esac
  fastboot getvar unlocked 2>&1 | grep -q "unlocked: yes" \
    || die "The bootloader is locked – first: fastboot flashing unlock"

  local tmp; tmp=$(mktemp -d)
  unzip -q -o "$img" -d "$tmp"
  c "Making slot a active"
  fastboot --set-active=a
  # 1) Boot images into BOTH slots. recovery belongs to it: the Phone (3a)
  #    has its own recovery_a/_b. Explicit suffixes, because the Nothing
  #    bootloader reports no has-slot for init_boot/recovery/... and fastboot
  #    would then not append _a.
  local p sl n
  for p in boot init_boot vendor_boot recovery dtbo vbmeta vbmeta_system vbmeta_vendor; do
    [ -f "$tmp/$p.img" ] || continue
    n=0
    for sl in a b; do
      c "flash ${p}_$sl"
      if flash_part "${p}_$sl" "$tmp/$p.img"; then n=$((n+1)); else warn "${p}_$sl does not exist"; fi
    done
    [ "$n" -gt 0 ] || { c "flash $p"; flash_part "$p" "$tmp/$p.img" || die "$p could not be flashed"; }
  done
  # 2) System partitions with fastbootd (userspace fastboot in the recovery)
  c "→ fastbootd (the Noxis recovery starts, then it continues by itself)"
  fastboot reboot fastboot
  wait_fastbootd || die "fastbootd not reached – phone: Recovery → Advanced → Enter fastboot, then ./noxis.sh direct"
  write_system "$tmp" a
  rm -rf "$tmp"
  fastboot reboot
  cat <<EOF

  First boot: Nothing logo → Noxis logo. This takes 5-15 minutes
  (setting up encryption, optimising apps). Do not press anything.
  If the recovery shows "Cannot load Android system": choose
  "Factory data reset", then "Reboot system now".

  After that:
   1. Set up the phone, then Developer options → USB debugging on
      → on the PC: ./noxis.sh postinstall   (Mullvad, Tor Browser, KernelSU manager)
   2. Open the KernelSU app → shows "Working" + kernel version.
   3. Root is blocked for ALL apps. Grant it only one by one:
      KernelSU → Superuser → tap the app → allow root.
   4. Open Mullvad and log in – there is no internet before that (kill switch).
   5. The bootloader STAYS unlocked – do NOT run "fastboot flashing lock",
      that makes the device unbootable with Noxis OS.

  Boot hangs for more than 15 minutes: hold Volume down + Power 15 s → fastboot.
  Going back to Nothing OS always works (the bootloader stays unlocked).

EOF
}

# Write the system partitions (system, vendor, product, ...) into one slot
# with fastbootd: drop a pending update snapshot, free space in "super" (the
# other slot's logical partitions and *-cow leftovers), flash, wipe data.
write_system() {  # <folder with images> <slot>
  local w="$1" slot="$2" other=b p lp
  [ "$slot" = b ] && other=a
  fastboot getvar is-userspace 2>&1 | grep -q "is-userspace: yes" || die "not in fastbootd"
  c "Dropping a pending update (snapshot)"
  fastboot snapshot-update cancel || warn "no snapshot pending"
  c "Making slot $slot active"; fastboot --set-active="$slot"
  for lp in $(fastboot getvar all 2>&1 | sed -n 's/.*(bootloader) is-logical:\([^:]*\):yes.*/\1/p' | sort -u); do
    case "$lp" in
      *_"$other"|*-cow) c "deleting $lp"; fastboot delete-logical-partition "$lp" || true ;;
    esac
  done
  for p in system system_ext product vendor odm system_dlkm vendor_dlkm odm_dlkm; do
    [ -f "$w/$p.img" ] || continue
    c "flash $p"
    fastboot flash "$p" "$w/$p.img" || die "$p failed – send the output to Claude"
  done
  c "Wiping data (fresh start)"
  fastboot -w || warn "fastboot -w failed – then in the recovery: Format data"
}

# Write only the system partitions again (e.g. after ./noxis.sh sysextfix).
# Uses a repaired system_ext if there is one.
cmd_direct() {
  need fastboot "install android-tools"
  local img; img=$(latest img.zip)
  [ -f "$img" ] || die "Run ./noxis.sh sign first"
  local w="$REL/direct" p; rm -rf "$w"; mkdir -p "$w"
  c "Unpacking images"
  for p in system system_ext product vendor odm system_dlkm vendor_dlkm odm_dlkm; do
    unzip -q -o "$img" "$p.img" -d "$w" 2>/dev/null || true
  done
  local fix="$REL/sysextfix/system_ext-fix.img"
  [ -f "$fix" ] && { c "using the repaired system_ext"; cp -f "$fix" "$w/system_ext.img"; }
  ls -la "$w"
  if ! fastboot getvar is-userspace 2>&1 | grep -q "is-userspace: yes"; then
    fastboot devices | grep -q . || die "Phone not in fastboot (hold Volume down + Power)"
    c "→ fastbootd"; fastboot reboot fastboot
    wait_fastbootd || die "fastbootd not reached"
  fi
  write_system "$w" "${NOXIS_SLOT:-a}"
  rm -rf "$w"
  fastboot reboot
  c "The phone boots Noxis from slot ${NOXIS_SLOT:-a} – first boot 5-15 minutes"
}

# Debug: put this PC's ADB key into init_boot + recovery and switch ADB on at
# boot (Android's own force_debuggable mechanism, only works with an unlocked
# bootloader), so "adb logcat" works even while the boot hangs. For debugging
# only – afterwards flash the normal images again with ./noxis.sh flash.
cmd_debugadb() {
  need fastboot "install android-tools"
  need adb "install android-tools"
  local img key="$HOME/.android/adbkey.pub" mkb="$SRC/system/tools/mkbootimg" d="$REL/debug"
  img=$(latest img.zip)
  [ -f "$img" ] || die "Run ./noxis.sh sign first"
  [ -f "$key" ] || { adb start-server >/dev/null 2>&1; sleep 1; }
  [ -f "$key" ] || die "$key is missing – run 'adb devices' once"
  [ -f "$mkb/mkbootimg.py" ] || die "$mkb is missing (comes with ./noxis.sh sync)"
  c "Putting the PC key into init_boot + recovery"
  python3 "$NOXIS/tools/noxis_adbkey.py" "$img" "$key" "$mkb" "$d" || die "Repacking failed"
  if ! fastboot devices | grep -q .; then
    adb devices 2>/dev/null | grep -q "recovery$" && { c "Recovery → bootloader"; adb reboot bootloader; sleep 8; }
  fi
  fastboot devices | grep -q . || die "Phone not in fastboot (hold Volume down + Power for 15 s)"
  local p sl
  for p in init_boot recovery; do
    [ -f "$d/$p-adb.img" ] || continue
    for sl in a b; do c "flash ${p}_$sl (debug)"; fastboot flash "${p}_$sl" "$d/$p-adb.img"; done
  done
  fastboot reboot
  cat <<EOF

  The phone boots. As soon as the Noxis logo shows, watch the log live:
    while true; do if [ "\$(adb get-state 2>/dev/null)" = device ]; then adb logcat -b all | grep --line-buffered -E "FATAL|AndroidRuntime|F DEBUG|am_crash"; fi; sleep 1; done
  Later: ./noxis.sh flash for the normal images.

EOF
}

# Add privapp permissions to the XML inside an image, in place (same file =
# the SELinux label stays). Source: our file in the repo.
xml_add() {
  sudo test -f "$1" || die "$1 is missing in the image"
  sudo python3 - "$1" "$NOXIS/vendor/noxis/permissions/privapp-permissions-noxis.xml" <<'PY'
import re, sys
target, source = sys.argv[1:]
new = set(re.findall(r'name="([\w.]+)"', open(source).read()))
with open(target, "r+") as f:
    t = f.read()
    have = set(re.findall(r'name="([\w.]+)"', t))
    missing = sorted(p for p in new - have if p.startswith("android.permission."))
    if not missing:
        print("  nothing to add"); sys.exit(0)
    lines = "".join(f'        <permission name="{p}" />\n' for p in missing)
    t = t.replace("    </privapp-permissions>", lines + "    </privapp-permissions>", 1)
    f.seek(0); f.write(t); f.truncate()
    for p in missing: print("  added:", p)
PY
}

fs_type() {
  python3 - "$1" <<'PY'
import sys
with open(sys.argv[1], "rb") as f:
    head = f.read(4); f.seek(1024); sb = f.read(4); f.seek(1080); e4 = f.read(2)
if head == bytes.fromhex("3aff26ed"): print("sparse")
elif sb == bytes.fromhex("e2e1f5e0"): print("erofs")
elif e4 == bytes.fromhex("53ef"): print("ext4")
else: print("unknown-" + head.hex())
PY
}

# Real fix WITHOUT a rebuild for a boot loop caused by a missing privapp
# permission: unpack system_ext.img from the finished build, add the line to
# privapp-permissions-noxis.xml, pack it again. SELinux labels (xattrs) are
# kept (EROFS: extract as root with --xattrs; ext4: mounted and edited in
# place). Works because verified boot was switched off when flashing. Then
# write it with ./noxis.sh direct.
cmd_sysextfix() {
  need fastboot "install android-tools"
  local img; img=$(latest img.zip)
  [ -f "$img" ] || die "Run ./noxis.sh sign first"
  local w="$REL/sysextfix"; sudo rm -rf "$w"; mkdir -p "$w"
  c "Unpacking system_ext.img"
  unzip -q -o "$img" system_ext.img -d "$w" || die "system_ext.img is not in the package"
  # img.zip often contains "sparse" images (Android format) – unpack first
  local type; type=$(fs_type "$w/system_ext.img")
  if [ "$type" = sparse ]; then
    need simg2img "install dev-util/android-tools (contains simg2img)"
    c "Unpacking the sparse image"
    simg2img "$w/system_ext.img" "$w/system_ext.raw" && mv -f "$w/system_ext.raw" "$w/system_ext.img"
    type=$(fs_type "$w/system_ext.img")
  fi
  c "File system: $type"
  local x_rel="etc/permissions/privapp-permissions-noxis.xml" mnt="$w/mnt"
  case "$type" in
    erofs)
      need fsck.erofs "install sys-fs/erofs-utils"; need mkfs.erofs "install sys-fs/erofs-utils"
      # the help text says "--[no-]xattrs"
      fsck.erofs --help 2>&1 | grep -q "xattrs" \
        || die "fsck.erofs too old (no --xattrs) – update sys-fs/erofs-utils"
      sudo fsck.erofs --extract="$w/root" --xattrs --preserve "$w/system_ext.img" >/dev/null \
        || die "Unpacking failed"
      xml_add "$w/root/$x_rel"
      c "Packing system_ext.img again"
      sudo mkfs.erofs -zlz4hc "$w/system_ext-fix.img" "$w/root" >/dev/null || die "mkfs.erofs failed"
      sudo chown "$(id -u):$(id -g)" "$w/system_ext-fix.img"
      sudo rm -rf "$w/root"
      ;;
    ext4)
      need e2fsck "install sys-fs/e2fsprogs"; need resize2fs "install sys-fs/e2fsprogs"
      cp -f "$w/system_ext.img" "$w/system_ext-fix.img"
      # Android packs ext4 with shared blocks (read-only) – make room first
      # and unshare the blocks, then it can be written.
      truncate -s +512M "$w/system_ext-fix.img"
      e2fsck -fy -E unshare_blocks "$w/system_ext-fix.img" >/dev/null 2>&1 || true
      resize2fs "$w/system_ext-fix.img" >/dev/null 2>&1 || die "resize2fs failed"
      e2fsck -fy -E unshare_blocks "$w/system_ext-fix.img" >/dev/null 2>&1 || true
      mkdir -p "$mnt"
      sudo mount -o loop,rw "$w/system_ext-fix.img" "$mnt" || die "The image cannot be mounted writable"
      xml_add "$mnt/$x_rel" || { sudo umount "$mnt"; die "Changing the XML failed"; }
      sync; sudo umount "$mnt"
      e2fsck -fy "$w/system_ext-fix.img" >/dev/null 2>&1 || true
      resize2fs -M "$w/system_ext-fix.img" >/dev/null 2>&1 || true
      # Cut the file to the new file system size, otherwise it may no longer
      # fit into the super partition
      local size
      size=$(dumpe2fs -h "$w/system_ext-fix.img" 2>/dev/null \
        | awk -F: '/^Block count/{gsub(/ /,"",$2);c=$2} /^Block size/{gsub(/ /,"",$2);b=$2} END{print c*b}')
      [ "${size:-0}" -gt 0 ] && truncate -s "$size" "$w/system_ext-fix.img"
      ;;
    *) die "system_ext.img is $type – send the output to Claude" ;;
  esac
  ls -la "$w/system_ext.img" "$w/system_ext-fix.img"
  c "Repaired image ready. Write it: ./noxis.sh direct"
}

cmd_all() {
  [ -n "${1:-}" ] || die "./noxis.sh all <nothing-os-ota.zip>"
  cmd_check; cmd_sync; cmd_apps; cmd_blobs "$1"; cmd_keys; cmd_build; cmd_sign
}

case "${1:-}" in
  check)  cmd_check ;;
  opsec)  cmd_opsec ;;
  sync)   cmd_sync ;;
  vendor) cmd_vendor ;;
  apps)   cmd_apps ;;
  blobs)  shift; cmd_blobs "$@" ;;
  keys)   cmd_keys ;;
  build)  cmd_build ;;
  sign)   cmd_sign ;;
  flash)  cmd_flash ;;
  postinstall|nachinstall) cmd_postinstall ;;
  ksu)    cmd_ksu ;;
  eta)    python3 "$NOXIS/tools/noxis_eta.py" "$SRC/out" --every 30 ;;
  direct|direkt) cmd_direct ;;
  sysextfix) cmd_sysextfix ;;
  debugadb) cmd_debugadb ;;
  publish) cmd_publish ;;
  cleanup) cmd_cleanup ;;
  all)    shift; cmd_all "$@" ;;
  *) sed -n '5,31p' "$0" ;;
esac
