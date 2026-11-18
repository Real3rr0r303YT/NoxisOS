#!/usr/bin/env bash
# ============================================================
#  Noxis OS – Build-Werkzeug (Android 17 / LineageOS 24.0)
#  Gerät: Nothing Phone (3a) / (3a) Pro  –  "asteroids"
#
#  ./noxis.sh check              Rechner prüfen (RAM, Platte, Tools)
#  ./noxis.sh sync               Quellcode holen (--depth=1, ~110 GB) + Noxis einbinden
#  ./noxis.sh apps               Kamera/PDF, Firefox (Fennec), Mullvad, Tor, KernelSU-Manager
#  ./noxis.sh blobs <ota.zip>    Herstellerdateien aus Nothing-OS-OTA ziehen
#  ./noxis.sh blobs <ota.zip> --neu
#                                dto., aber die Dateiliste aus dem Abzug neu
#                                schreiben - noetig, wenn der Abzug ein
#                                anderer Nothing-OS-Stand ist als der Baum
#  ./noxis.sh keys               Eigene Signaturschlüssel
#  ./noxis.sh build              Kompilieren (user-Build, KernelSU im Kernel)
#  ./noxis.sh opsec              Gebautes Image gegen die OPSEC-Regeln prüfen
#  ./noxis.sh sign               Signieren → OTA + Images → Desktop, out/ löschen
#  ./noxis.sh cleanup            ROM auf den Desktop, out/ löschen (NOXIS_KEEP_OUT=1 behält)
#  ./noxis.sh flash              Aufs Handy installieren (geführt, Bootloader bleibt offen)
#  ./noxis.sh publish            OTA als GitHub-Release hochladen → Handy: Einstellungen → System → Updater
#  ./noxis.sh all <ota.zip>      sync → apps → blobs → keys → build → sign
# ============================================================
set -Eeuo pipefail
# Bricht das Skript an einer Stelle ab, die keine eigene Meldung hat, soll
# man das sehen - mit Zeile und Befehl. Ohne das endet es stumm, und der
# naechste Schritt laeuft mit altem Stand weiter, als waere nichts gewesen.
trap 'printf "\033[1;31m[fehler]\033[0m unerwarteter Abbruch in noxis.sh Zeile %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

NOXIS="$(cd "$(dirname "$0")" && pwd)"
SRC="${NOXIS_SRC:-$HOME/noxis-src}"
KEYS="${NOXIS_KEYS:-$HOME/.noxis-keys}"
# Nicht OUT nennen: envsetup.sh von LineageOS setzt OUT auf out/target/product/...
# und haette die fertige ROM sonst dorthin umgeleitet (wird danach geloescht).
REL="${NOXIS_OUT:-$NOXIS/release}"
BRANCH="lineage-24.0"
DEVICE="asteroids"
VARIANT="${NOXIS_VARIANT:-user}"
SUBJECT="${NOXIS_SUBJECT:-/C=DE/O=Noxis OS/OU=Noxis/CN=Noxis OS}"
KSU_TAG="${NOXIS_KSU_TAG:-v3.3.1}"

c()    { printf '\033[38;5;111m[noxis]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m[fehler]\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 fehlt – $2"; }
confirm() { read -rp "$1 [ja/N] " a; [ "$a" = "ja" ]; }

envsetup() {
  cd "$SRC"
  # LineageOS-Skripte lassen Befehle absichtlich fehlschlagen; die Falle von
  # oben wuerde dort Fehlalarm geben. Ab hier meldet die() echte Fehler.
  trap - ERR
  set +Eu
  # shellcheck disable=SC1091
  source build/envsetup.sh >/dev/null
  breakfast "$DEVICE" "$VARIANT" >/dev/null || die "breakfast $DEVICE $VARIANT fehlgeschlagen"
  set -u
}

# Die Soong-Analyse ist ein einzelner Prozess mit 15-20 GB. Mit wenig RAM
# schiesst der Kernel ihn ab ("signal: killed"), auch wenn die Swapdatei
# frei ist - sie ist zu langsam. Komprimierter Swap im RAM (zram) reicht.
# Gilt bis zum Neustart; ist er schon da, passiert nichts.
zram_an() {
  local ram
  ram=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
  [ "$ram" -ge 32 ] && return 0
  if grep -q '^/dev/zram' /proc/swaps; then
    c "zram-Swap schon aktiv"
  else
    c "Wenig RAM ($ram GB): richte 20 GB zram-Swap ein (sudo-Passwort)"
    local z
    sudo modprobe zram \
      && z=$(sudo zramctl --find --size 20G --algorithm zstd) \
      && sudo mkswap "$z" >/dev/null && sudo swapon -p 100 "$z" \
      || { warn "zram ging nicht – die Analyse kann abgeschossen werden (signal: killed)"; return 0; }
  fi
  sudo sysctl -q vm.swappiness=180 vm.watermark_scale_factor=200 vm.page-cluster=0 || true
}

# Einige Projekte (u.a. external/chromium-webview) liegen als Git-LFS vor.
# Ohne git-lfs beim Sync bleiben dort nur kleine Textzeiger statt der APKs,
# und der Bau scheitert erst nach Stunden ("aapt2 dump badging ... webview.apk").
lfs_holen() {
  command -v git-lfs >/dev/null 2>&1 || die "git-lfs fehlt.
       Gentoo: sudo emerge --ask dev-vcs/git-lfs   Debian/Ubuntu: sudo apt install git-lfs"
  git lfs install --skip-repo >/dev/null
  c "Git-LFS-Dateien holen (WebView usw.)"
  ( cd "$SRC" && repo forall -j4 -c 'git lfs pull >/dev/null 2>&1 || true' )
}

# Prueft vor dem Bauen, ob noch LFS-Zeiger statt echter Dateien da sind.
lfs_pruefen() {
  local apk="$SRC/external/chromium-webview/prebuilt/arm64/webview.apk"
  if [ -f "$apk" ] && head -c 40 "$apk" | grep -q "git-lfs"; then
    warn "WebView ist nur ein Git-LFS-Zeiger – hole die echten Dateien"
    lfs_holen
    head -c 40 "$apk" | grep -q "git-lfs" && die "WebView immer noch nicht geladen – Internet pruefen, dann nochmal"
  fi
  return 0
}

# Vorsignierte Fremd-APKs (Tor Browser, Mullvad ...) muessen unveraendert
# ins System. Android 17 verlangt dafuer unkomprimierte .so-Bibliotheken; manche
# Hersteller liefern sie aber komprimiert aus ("Contains compressed JNI
# libraries"). Umpacken wuerde ihre Signatur zerstoeren. Solche Apps kommen
# deshalb nicht ins Image, sondern werden nach dem Flashen per adb installiert
# (./noxis.sh nachinstall) - sie bleiben so original signiert und updatebar.
NACH="$NOXIS/nachinstallieren"
apks_pruefen() {
  local d name apk
  for d in "$SRC/vendor/noxis/prebuilt"/*/; do
    name=$(basename "$d"); apk="$d$name.apk"
    [ -f "$apk" ] && grep -qs "preprocessed: true" "$d/Android.bp" || continue
    if unzip -v "$apk" 2>/dev/null | awk '$NF ~ /^lib\/.*\.so$/ && $2 != "Stored" {f=1} END {exit !f}'; then
      mkdir -p "$NACH"
      cp -f "$apk" "$NACH/$name.apk"
      rm -rf "$d" "$NOXIS/vendor/noxis/prebuilt/$name"
      warn "$name hat komprimierte Bibliotheken – kommt nicht ins Image,
       sondern nach dem Flashen per ./noxis.sh nachinstall"
    fi
  done
  return 0
}

cmd_nachinstall() {
  need adb "android-tools installieren"
  ls "$NACH"/*.apk >/dev/null 2>&1 || { c "Nichts nachzuinstallieren"; return 0; }
  c "Handy mit USB-Debugging verbinden (Einstellungen → Entwickleroptionen)"
  adb wait-for-device
  local a
  for a in "$NACH"/*.apk; do
    c "installiere $(basename "$a" .apk)"
    adb install -r "$a" || warn "$(basename "$a") ging nicht"
  done
}

# ------------------------------------------------------------ check
cmd_check() {
  local ram disk
  ram=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
  disk=$(df -BG --output=avail "$(dirname "$SRC")" | tail -1 | tr -dc 0-9)
  c "RAM: ${ram} GB (empfohlen 32+, mit 16 GB nur mit 32 GB Swap)"
  c "Freier Platz bei $(dirname "$SRC"): ${disk} GB (nötig ~400 GB)"
  local swap
  swap=$(awk '/SwapTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
  c "Swap: ${swap} GB"
  if [ "$ram" -lt 24 ]; then
    warn "Wenig RAM. Der Bau laeuft trotzdem, aber mit $(( ram / 4 )) statt $(nproc) Jobs und entsprechend langsam."
    [ $(( ram + swap )) -lt 32 ] && warn "RAM + Swap unter 32 GB – einzelne Uebersetzer koennen abgeschossen werden.
       Swapdatei anlegen:
         sudo fallocate -l 32G /swapfile && sudo chmod 600 /swapfile
         sudo mkswap /swapfile && sudo swapon /swapfile"
  fi
  if [ "$disk" -lt 350 ]; then
    warn "Zu wenig Platz: ${disk} GB da, etwa 400 GB noetig (110 GB Quellcode, Rest out/ und ccache).
       Das bricht erst nach Stunden ab. Was am meisten belegt:
         sudo du -sh /var/lib/docker ~/Desktop/noxis-linux ~/noxis-backup 2>/dev/null
       Docker-Volume vom Linux-Bau loeschen (wird beim naechsten Bau neu geholt):
         sudo docker volume rm noxis-kernel && sudo docker system prune -af"
  fi
  if ! git config --global user.name >/dev/null 2>&1 \
     || ! git config --global user.email >/dev/null 2>&1; then
    warn "Git-Identitaet fehlt - repo bricht sonst beim sync ab:
         git config --global user.name \"DEIN-NAME\"
         git config --global user.email \"DEIN-NAME@users.noreply.github.com\""
  fi
  for t in git git-lfs python3 curl zip unzip openssl ccache fastboot adb fsck.erofs; do
    command -v "$t" >/dev/null && echo "  ✓ $t" || echo "  ✗ $t"
  done
  command -v repo >/dev/null && echo "  ✓ repo" || echo "  ✗ repo  →  curl -o ~/.local/bin/repo https://storage.googleapis.com/git-repo-downloads/repo && chmod +x ~/.local/bin/repo"
  cat <<'EOF'

Pakete:
  Gentoo:  emerge -av dev-vcs/git dev-vcs/git-lfs dev-util/ccache app-arch/zip app-arch/unzip \
           sys-fs/erofs-utils \
           dev-lang/python sys-devel/bc sys-devel/bison sys-devel/flex dev-libs/openssl \
           app-arch/lz4 dev-util/android-tools sys-libs/ncurses media-gfx/imagemagick
  Ubuntu:  sudo apt install erofs-utils bc bison build-essential ccache curl flex g++-multilib gcc-multilib git \
           git-lfs gnupg gperf imagemagick lib32readline-dev lib32z1-dev libelf-dev liblz4-tool \
           lz4 libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool \
           squashfs-tools xsltproc zip zlib1g-dev python3 android-sdk-libsparse-utils
EOF
}

# ------------------------------------------------------------ sync
# Platz dort pruefen, wo wirklich gebaut wird. Ein Android-Bau laeuft stunden-
# bis tagelang; wenn die Platte dabei volllaeuft, ist die ganze Zeit verloren.
# Lieber hier abbrechen. NOXIS_SRC zeigt auf eine andere Platte, wenn die
# Systemplatte zu klein ist.
need_space() {  # $1 = Pfad, $2 = noetige GB, $3 = wofuer
  local free
  mkdir -p "$1" 2>/dev/null || true
  free=$(df -BG --output=avail "$1" 2>/dev/null | tail -1 | tr -dc 0-9)
  [ -n "$free" ] || return 0
  if [ "$free" -lt "$2" ]; then
    die "Zu wenig Platz fuer $3: $free GB frei unter $1, noetig etwa $2 GB.
       Andere Platte nehmen:  export NOXIS_SRC=/pfad/zur/platte/noxis-src
       Belegung ansehen:      du -xh --max-depth=1 \$HOME | sort -rh | head
       Pruefung uebergehen:   NOXIS_SKIP_SPACE=1 (auf eigenes Risiko)"
  fi
  c "Platz unter $1: $free GB frei"
}

# repo legt im Manifest-Baum eigene Commits an und braucht dafuer eine
# globale Identitaet. Fehlt sie, bricht es erst nach dem Initialisieren ab -
# also vorher fragen.
git_identitaet() {
  git config --global user.name >/dev/null 2>&1 \
    && git config --global user.email >/dev/null 2>&1 && return 0
  die "Git kennt dich noch nicht - repo braucht das. Einmalig setzen:
         git config --global user.name \"DEIN-NAME\"
         git config --global user.email \"DEIN-NAME@users.noreply.github.com\"
       Die Noreply-Adresse von GitHub haelt deine echte Mail aus den Commits heraus."
}

cmd_sync() {
  need repo "siehe ./noxis.sh check"
  need git-lfs "git-lfs installieren"
  git_identitaet
  command -v git-lfs >/dev/null 2>&1 || die "git-lfs fehlt – sonst fehlen nach dem Sync u.a. die WebView-APKs.
       Gentoo: sudo emerge --ask dev-vcs/git-lfs"
  [ "${NOXIS_SKIP_SPACE:-0}" = 1 ] || need_space "$(dirname "$SRC")" 150 "den Quellcode"
  mkdir -p "$SRC" && cd "$SRC"
  if [ ! -d .repo ]; then
    c "LineageOS $BRANCH initialisieren"
    repo init -u https://github.com/LineageOS/android.git -b "$BRANCH" --git-lfs --no-clone-bundle --depth=1
  fi
  mkdir -p .repo/local_manifests
  cp "$NOXIS/manifest/noxis.xml" .repo/local_manifests/noxis.xml
  c "Quellcode synchronisieren (beim ersten Mal mehrere Stunden)"
  # --depth gehoert zu 'repo init', nicht zu 'repo sync' - dort ist es keine
  # gueltige Option und bricht sofort ab. Die flache Tiefe steht seit dem
  # init oben in der Manifest-Konfiguration und gilt fuer jeden sync.
  #
  # Gleichzeitige Abrufe nach RAM begrenzen: jeder ist ein eigener
  # git-Prozess, und auf einem Rechner mit wenig Speicher holt der
  # OOM-Killer sonst mitten im Abruf welche weg.
  local jobs
  jobs=$(awk '/MemTotal/ {j=int($2/1024/1024/2); print (j<2 ? 2 : (j>8 ? 8 : j))}' /proc/meminfo)
  [ "$jobs" -gt "$(nproc)" ] && jobs=$(nproc)
  c "  $jobs gleichzeitige Abrufe"
  repo sync -c -j"$jobs" --force-sync --no-clone-bundle --no-tags --optimized-fetch --prune \
    || repo sync -c -j2 --force-sync --no-clone-bundle --no-tags
  lfs_holen
  cmd_vendor
}

cmd_vendor() {
  c "vendor/noxis in den Quellbaum kopieren"
  mkdir -p "$SRC/vendor/noxis"
  find "$SRC/vendor/noxis" -mindepth 1 -maxdepth 1 ! -name prebuilt -exec rm -rf {} +
  cp -a "$NOXIS/vendor/noxis/." "$SRC/vendor/noxis/"
  c "Noxis-Patches anwenden"
  python3 "$NOXIS/tools/noxis_patch.py" "$SRC"
}

# ------------------------------------------------------------ apps
gh_latest_asset() {  # <owner/repo> <regex>  →  Download-URL
  local repo="$1" re="$2" tag
  tag=$(curl -fsSIL -o /dev/null -w '%{url_effective}' "https://github.com/$repo/releases/latest" | sed 's,.*/tag/,,')
  [ -n "$tag" ] || return 1
  curl -fsSL "https://github.com/$repo/releases/expanded_assets/$tag" \
    | grep -oE "/$repo/releases/download/[^\"]+" | grep -E "$re" | head -1 | sed 's,^,https://github.com,'
}

gh_tag_asset() {  # <owner/repo> <tag> <regex>  →  Download-URL eines festen Releases
  curl -fsSL "https://github.com/$1/releases/expanded_assets/$2" \
    | grep -oE "/$1/releases/download/[^\"]+" | grep -E "$3" | head -1 | sed 's,^,https://github.com,'
}

tor_url() {  # neueste stabile Tor-Browser-Version für arm64
  local ver
  ver=$(curl -fsSL --max-time 60 https://dist.torproject.org/torbrowser/ | grep -oE 'href="[0-9]+\.[0-9]+(\.[0-9]+)?/"' \
        | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | sort -V | tail -1) || true
  [ -n "$ver" ] && echo "https://dist.torproject.org/torbrowser/$ver/tor-browser-android-aarch64-$ver.apk"
  return 0
}

install_fennec() {  # Firefox ohne Google/Telemetrie (Fennec F-Droid), arm64-Variante
  local api ver codes code dir="$NOXIS/vendor/noxis/prebuilt/Fennec"
  api=$(curl -fsSL --max-time 60 https://f-droid.org/api/v1/packages/org.mozilla.fennec_fdroid) \
    || { warn "Fennec: F-Droid nicht erreichbar – wird weggelassen"; return 0; }
  # Ungeschuetzt wuerde eine Formataenderung bei F-Droid wegen 'set -e' den
  # ganzen Lauf abbrechen. Eine fehlende App soll aber nur fehlen, wie bei
  # install_apk auch.
  ver=$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); s=d["suggestedVersionCode"]; print(next(p["versionName"] for p in d["packages"] if p["versionCode"]==s))' "$api" 2>/dev/null) \
    || { warn "Fennec: F-Droid-Antwort unerwartet – wird weggelassen"; return 0; }
  [ -n "$ver" ] || { warn "Fennec: keine Version gefunden – wird weggelassen"; return 0; }
  codes=$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(" ".join(str(p["versionCode"]) for p in d["packages"] if p["versionName"]==sys.argv[2]))' "$api" "$ver" 2>/dev/null) \
    || { warn "Fennec: keine Pakete zu $ver – wird weggelassen"; return 0; }
  mkdir -p "$dir"
  for code in $codes; do
    curl -fsSL --max-time 900 -o "$dir/Fennec.apk.part" "https://f-droid.org/repo/org.mozilla.fennec_fdroid_$code.apk" || continue
    if unzip -l "$dir/Fennec.apk.part" 2>/dev/null | grep -q 'lib/arm64-v8a/'; then
      mv "$dir/Fennec.apk.part" "$dir/Fennec.apk"
      c "Fennec ← F-Droid $ver ($code, arm64-v8a)"
      cat > "$dir/Android.bp" <<'EOF'
android_app_import {
    name: "Fennec",
    apk: "Fennec.apk",
    presigned: true,
    // Signatur v2/v3 bleibt nur heil, wenn Soong die APK nicht anfasst
    preprocessed: true,
    product_specific: true,
    dex_preopt: {
        enabled: false,
    },
}
EOF
      return 0
    fi
  done
  rm -f "$dir/Fennec.apk.part"; rmdir "$dir" 2>/dev/null || true
  warn "Fennec: keine arm64-APK gefunden – Browser wird weggelassen"
}

install_apk() {  # <Name> <url> <privileged:true|false>
  local name="$1" url="$2" priv="$3" dir
  dir="$NOXIS/vendor/noxis/prebuilt/$name"
  [ -n "$url" ] || { warn "$name: keine Download-Adresse gefunden – wird weggelassen"; return 0; }
  mkdir -p "$dir"
  c "$name ← $url"
  # --max-time, damit ein haengender Server den Lauf nicht endlos blockiert.
  if ! curl -fL --progress-bar --connect-timeout 20 --max-time 1800 -o "$dir/$name.apk.part" "$url"; then
    warn "$name: Download fehlgeschlagen – wird weggelassen"
    rm -f "$dir/$name.apk.part"; rmdir "$dir" 2>/dev/null || true
    return 0
  fi
  mv "$dir/$name.apk.part" "$dir/$name.apk"
  cat > "$dir/Android.bp" <<EOF
android_app_import {
    name: "$name",
    apk: "$name.apk",
    presigned: true,
    // Signatur v2/v3 bleibt nur heil, wenn Soong die APK nicht anfasst
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

# ------------------------------------------------------------ 3rr0r's own apps (built by GitHub Actions)
# name → LineageOS app it replaces (empty = added next to the stock app)
NOXIS_APPS_REPO="${NOXIS_APPS_REPO:-Real3rr0r303YT/NoxisOS}"
NOXIS_OWN_APPS="NoxisCalendar:Etar NoxisClock:DeskClock NoxisCalculator:ExactCalculator NoxisNotes: NoxisCall: NoxisBattery: NoxisLauncher:"

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
      echo "    // Testschluessel beim Bauen, beim Signieren (noxis.sh sign) durch den Noxis-Schluessel ersetzt"
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

cmd_apps() {
  need curl "curl installieren"
  install_own_apps
  install_apk GrapheneCamera    "$(gh_latest_asset GrapheneOS/Camera '\.apk$' || true)" false
  install_apk GraphenePdfViewer "$(gh_latest_asset GrapheneOS/PdfViewer '\.apk$' || true)" false
  # Standard-Browser: Cromite (gehärtetes Chromium – Website-Isolierung, starke Renderer-Sandbox)
  install_apk Cromite           "$(gh_latest_asset uazo/cromite 'arm64_ChromePublic\.apk$' || true)" false
  install_fennec
  install_apk MullvadVPN        "https://mullvad.net/download/app/apk/latest" false
  install_apk TorBrowser        "$(tor_url)" false
  # Manager muss zur KernelSU-Version im Kernel passen (vendored v3.3.1) und offiziell signiert sein
  install_apk KernelSU          "$(gh_tag_asset tiann/KernelSU "$KSU_TAG" 'KernelSU.*\.apk$' || true)" false
  [ -d "$SRC/vendor" ] && cmd_vendor
  return 0
}

# ------------------------------------------------------------ blobs
cmd_blobs() {
  local ota="${1:-}"
  [ -f "$ota" ] || [ -d "$ota" ] || die "Pfad zur Nothing-OS-OTA (Vollversion .zip) oder einem Dump angeben"
  # Die Partitionen des Nothing-OS sind EROFS. Ohne fsck.erofs entpackt
  # extract-files.py gar nichts, meldet das aber nur als Warnung und laeuft
  # weiter - am Ende stehen dann tausend Zeilen "file not found", und die
  # eigentliche Ursache steht ganz oben im Protokoll.
  command -v fsck.erofs >/dev/null 2>&1 \
    || die "fsck.erofs fehlt - ohne das bleiben alle Partitionen zu.
       Gentoo:  sudo emerge -av sys-fs/erofs-utils
       Ubuntu:  sudo apt install erofs-utils"
  ota="$(cd "$(dirname "$ota")" && pwd)/$(basename "$ota")"
  local want
  want=$(sed -n 's/^## .*are from the \(.*\) release.*/\1/p' "$SRC/device/nothing/$DEVICE/proprietary-files.txt" | head -1)
  [ -n "$want" ] && c "Gerätebaum erwartet Nothing OS: $want"
  # Stand des Abzugs mit dem erwarteten vergleichen, bevor irgendetwas
  # passiert. Ein anderer Stand fuehrt nicht zu einem Fehler, sondern zu
  # vielen: abweichende Pruefsummen, fehlende und neue Abhaengigkeiten, und
  # jeder davon zeigt sich erst beim Bau. Das hat einmal eine Stunde
  # gekostet - also lieber hier anhalten.
  if [ -n "$want" ] && [ -d "$ota" ] && [ "${NOXIS_ANDERER_STAND:-0}" != 1 ]; then
    local prop hat=""
    for prop in "$ota/system/build.prop" "$ota/system/system/build.prop" \
                "$ota/vendor/build.prop" "$ota/product/etc/build.prop"; do
      [ -f "$prop" ] || continue
      hat=$(grep -m1 -E '^ro\.(build\.display\.id|system\.build\.version\.incremental|vendor\.build\.version\.incremental)=' "$prop" | cut -d= -f2-)
      [ -n "$hat" ] && break
    done
    if [ -n "$hat" ] && ! printf '%s' "$hat" | grep -qF "$want"; then
      die "Der Abzug ist ein anderer Nothing-OS-Stand:
         Abzug:     $hat
         erwartet:  $want
       Damit passen Pruefsummen und Abhaengigkeiten nicht, und der Bau
       scheitert an immer neuen Stellen. Den passenden Stand gibt es hier
       (Phone (3a) -> $want -> 'OTA Images'):
         https://spike0en.github.io/nothing_archive/docs/firmware
       Bewusst trotzdem weitermachen:  NOXIS_ANDERER_STAND=1 ./noxis.sh blobs ..."
    elif [ -n "$hat" ]; then
      c "Abzug passt: $hat"
    fi
  fi
  cd "$SRC/device/nothing/$DEVICE"
  # Der Geraetebaum schreibt Dateinamen und Pruefsummen einer bestimmten
  # Nothing-OS-Fassung fest. Ist der eigene Abzug eine andere, passt beides
  # nicht: Pruefsummen weichen ab, und regionsfremde Dateien (Verizon in
  # US-Firmware) fehlen ganz. Mit --neu laesst extract-files.py die Liste
  # aus dem vorhandenen Abzug neu schreiben.
  local regen=""
  case "${2:-}${NOXIS_REGEN:+--neu}" in *--neu*) regen="--regenerate" ;; esac
  if [ -n "$regen" ]; then
    c "Herstellerdateien extrahieren, Dateiliste neu schreiben (anderer Nothing-OS-Stand)"
    warn "proprietary-files.txt wird dabei neu geschrieben. Dabei koennen
       Umbenennungs-Eintraege (quelle:ziel) verloren gehen, und der Bau
       meldet dann 'depends on undefined module'. Zuruecksetzen:
         cd $SRC/device/nothing/$DEVICE && git checkout proprietary-files.txt
       Fuer fehlende Verizon/Miracast-Dateien ist --neu nicht noetig, die
       nimmt tools/blobs-weglassen.txt ohnehin heraus."
  else
    c "Herstellerdateien extrahieren (WLAN, Mobilfunk/IMS, NFC, eSIM, Kamera, Firmware)"
  fi
  # Noxis-Patches zuerst: einige betreffen die Dateiliste und extract-files.py
  # selbst (etwa die Kamera-Bibliothek postproc@1.0-nt). Sie sind wiederholbar
  # und greifen damit auch nach einem 'git checkout' der Liste.
  c "Noxis-Patches auf den Geraetebaum anwenden"
  python3 "$NOXIS/tools/noxis_patch.py" "$SRC" || die "Noxis-Patches fehlgeschlagen"
  # Was Noxis bewusst weglaesst, vor jeder Extraktion aus der Liste nehmen -
  # auch nach einem 'repo sync', der proprietary-files.txt zuruecksetzt.
  c "Weggelassene Herstellerdateien aus der Liste nehmen"
  { grep -v '^[[:space:]]*\(#\|$\)' "$NOXIS/tools/blobs-weglassen.txt" || true; } \
    | python3 "$NOXIS/tools/noxis_blobs_clean.py" "$SRC/device/nothing/$DEVICE/proprietary-files.txt" \
    || die "Liste der weggelassenen Dateien liess sich nicht anwenden"
  # Umgekehrt: was neuere Nothing-OS-Staende zusaetzlich brauchen. Nur
  # nachtragen, wenn die Datei im entpackten Abzug liegt - sonst wuerde die
  # Extraktion an einem Eintrag ohne Datei scheitern.
  local liste_pf="$SRC/device/nothing/$DEVICE/proprietary-files.txt" dazu
  if [ -d "$ota" ] && [ -f "$NOXIS/tools/blobs-dazu.txt" ]; then
    # '|| true': ohne Eintraege liefert grep 1, und mit pipefail wuerde das
    # Skript hier stumm enden - genau so ist die Extraktion einmal ausgefallen.
    { grep -v '^[[:space:]]*\(#\|$\)' "$NOXIS/tools/blobs-dazu.txt" || true; } | while read -r dazu; do
      grep -qF "$dazu" "$liste_pf" && continue
      if [ -e "$ota/$dazu" ]; then
        printf '%s\n' "$dazu" >> "$liste_pf"
        c "  nachgetragen: $dazu"
      else
        c "  nicht im Abzug, bleibt weg: $dazu"
      fi
    done
  fi
  if [ -z "$regen" ]; then
    ./extract-files.py "$ota"
  else
    # extract-files.py sagt selbst, welche Dateien es nicht findet
    # ("<pfad>: file not found") und bricht dann ab. Genau diese Eintraege
    # nehmen wir aus der Liste und versuchen es erneut. Das haengt damit an
    # dem, was das Werkzeug feststellt, statt an einer Annahme darueber, wie
    # der Abzug aufgebaut ist.
    # Auf den Rueckgabewert ist kein Verlass: extract-files.py endet mit 0,
    # auch wenn es "Some files failed to process, exiting" schreibt. Also
    # entscheidet, was in der Ausgabe steht.
    local log liste versuch=0
    log=$(mktemp); liste="$SRC/device/nothing/$DEVICE/proprietary-files.txt"
    while [ "$versuch" -le 3 ]; do
      ./extract-files.py --regenerate "$ota" 2>&1 | tee "$log" || true
      # Farbcodes und Wagenruecklauf vorher abziehen: extract-files.py faerbt
      # Fehlerzeilen ein, und dann passt ein Muster mit '^' und '$' nicht.
      fehlend=$(sed 's/\x1b\[[0-9;]*[A-Za-z]//g; s/\r$//' "$log" \
                | sed -n 's/^[[:space:]]*\(.*[^[:space:]]\):[[:space:]]*file not found[[:space:]]*$/\1/p' \
                | sort -u)
      if [ -z "$fehlend" ]; then
        # Abgebrochen, aber nichts erkannt: zeigen, wie die Zeilen wirklich
        # aussehen, statt still aufzugeben.
        if grep -q "failed to process" "$log"; then
          warn "Extraktion abgebrochen, aber keine 'file not found'-Zeile erkannt. So sehen sie aus:"
          grep -a "file not found" "$log" | head -3 | cat -v | sed 's/^/       /'
        fi
        break
      fi
      versuch=$((versuch + 1))
      c "Eintraege ohne Datei im Abzug entfernen (Durchgang $versuch)"
      if ! printf '%s\n' "$fehlend" | python3 "$NOXIS/tools/noxis_blobs_clean.py" "$liste"; then
        rm -f "$log"; die "Aufraeumen fehlgeschlagen"
      fi
    done
    rm -f "$log"
  fi
  [ -f "$SRC/vendor/nothing/$DEVICE/$DEVICE-vendor.mk" ] || die "Extraktion unvollständig"
  c "OK: vendor/nothing/$DEVICE"
}

# ------------------------------------------------------------ keys
make_key4096() {  # <pfad-ohne-endung> <subject>
  local tmp
  tmp=$(mktemp -d)
  cp "$SRC/development/tools/make_key" "$tmp/make_key"
  sed -i 's|2048|4096|g' "$tmp/make_key"
  printf '\n' | "$tmp/make_key" "$1" "$2" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}

cmd_keys() {
  [ -x "$SRC/development/tools/make_key" ] || die "Erst ./noxis.sh sync"
  mkdir -p "$KEYS" && chmod 700 "$KEYS"
  for cert in releasekey platform shared media networkstack sdk_sandbox bluetooth nfc testkey; do
    [ -f "$KEYS/$cert.pk8" ] && continue
    c "Schlüssel: $cert"
    printf '\n' | "$SRC/development/tools/make_key" "$KEYS/$cert" "$SUBJECT" >/dev/null 2>&1 || true
    [ -f "$KEYS/$cert.pk8" ] || die "make_key $cert fehlgeschlagen"
  done
  if [ ! -f "$KEYS/avb.pem" ]; then
    c "Verified-Boot-Schlüssel (RSA-4096)"
    openssl genrsa -out "$KEYS/avb.pem" 4096 2>/dev/null
  fi
  chmod 600 "$KEYS"/*
  c "Schlüssel liegen in $KEYS"
  warn "SICHERN! Ohne diese Schlüssel lassen sich keine Updates mehr über Noxis-OTA einspielen (nur Neuinstallation mit Datenverlust)."
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
  [ -f "$SRC/vendor/nothing/$DEVICE/$DEVICE-vendor.mk" ] || die "Erst ./noxis.sh blobs <ota.zip>"
  # out/ waechst beim Bauen auf ueber 100 GB.
  # Was out/ schon belegt, ist vom Bedarf abzuziehen - sonst scheitert jeder
  # Weiterbau nach einem Abbruch an der Platzpruefung.
  local schon=0 noetig
  [ -d "$SRC/out" ] && schon=$(du -sBG "$SRC/out" 2>/dev/null | cut -f1 | tr -dc 0-9 || echo 0)
  noetig=$(( 130 - ${schon:-0} )); [ "$noetig" -lt 15 ] && noetig=15
  [ "${NOXIS_SKIP_SPACE:-0}" = 1 ] || need_space "$SRC" "$noetig" "out/ (noch zu bauen, ${schon:-0} GB schon da)"
  cmd_vendor
  apks_pruefen
  lfs_pruefen
  zram_an
  envsetup
  # ccache ist aus: beim ersten Bau ist der Cache leer und bringt nichts, und
  # in den Bau-Sandboxen von Android 17 scheitert er mit "ccache: error: Not
  # a directory". Wer ihn fuer spaetere Neubauten will: NOXIS_CCACHE=1.
  if [ "${NOXIS_CCACHE:-0}" = 1 ] && command -v ccache >/dev/null; then
    mkdir -p "$HOME/.ccache-noxis"
    export USE_CCACHE=1 CCACHE_EXEC="$(command -v ccache)" CCACHE_DIR="$HOME/.ccache-noxis"
    ccache -M "${NOXIS_CCACHE_SIZE:-25G}" >/dev/null
  else
    unset USE_CCACHE CCACHE_EXEC
  fi
  # Ohne Begrenzung startet mka so viele Übersetzer, wie Kerne da sind. Jeder
  # davon braucht Speicher; auf einem Rechner mit wenig RAM endet das im
  # OOM-Killer, meist nach Stunden. Darum: ein Job je 4 GB.
  #
  # Swap zaehlt dabei mit, aber nur zur Haelfte. Nicht jeder Uebersetzer
  # braucht seinen Speicher gleichzeitig, also darf etwas davon ausgelagert
  # sein - voll gerechnet wuerde der Rechner aber nur noch auslagern statt
  # zu uebersetzen. Mit 14 GB RAM und 24 GB Swap ergibt das 6 statt 3 Jobs
  # und damit grob die halbe Bauzeit.
  local ram swap jobs
  ram=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
  swap=$(awk '/SwapTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
  jobs="${NOXIS_JOBS:-$(( (ram + swap / 2) / 4 ))}"
  [ "$jobs" -lt 2 ] && jobs=2
  [ "$jobs" -gt "$(nproc)" ] && jobs=$(nproc)
  c "Baue Noxis OS ($DEVICE-$VARIANT) mit $jobs Jobs (${ram} GB RAM + ${swap} GB Swap) – das dauert"
  if [ "$ram" -lt 24 ]; then
    warn "Wenig RAM: rechne mit vielen Stunden.
       Haengt der Rechner nur noch am Auslagern (Platte dauerlaeuft, nichts
       geht voran), mit weniger Jobs neu starten: NOXIS_JOBS=$(( jobs - 2 ))
       Mehr Jobs gehen auch: NOXIS_JOBS=n"
  fi
  mka -j"$jobs" target-files-package otatools \
    || die "Build fehlgeschlagen – im Log oben nach der ersten Zeile mit 'error:' suchen"
  c "Build fertig."
  cmd_opsec || die "OPSEC-Prüfung fehlgeschlagen – siehe oben"
  c "Weiter: ./noxis.sh sign"
}

# ------------------------------------------------------------ opsec
# Prüft das gebaute Image gegen die Noxis-Regeln. Die Gerätebäume kommen von
# fremden Projekten und ändern sich; was dort hereinkommt, soll hier auffallen
# und nicht erst auf dem Handy.
cmd_opsec() {
  local prod="$SRC/out/target/product/$DEVICE"
  [ -d "$prod" ] || die "Nichts gebaut – erst ./noxis.sh build"
  NOXIS_NACH="$NACH" "$NOXIS/tools/opsec-verify.sh" "$prod"
}

# ------------------------------------------------------------ sign
cmd_sign() {
  [ -f "$KEYS/releasekey.pk8" ] || die "Erst ./noxis.sh keys"
  envsetup
  local tf
  local pout="${ANDROID_PRODUCT_OUT:-$SRC/out/target/product/$DEVICE}"
  tf=$(ls -t "$pout"/obj/PACKAGING/target_files_intermediates/*-target_files*.zip 2>/dev/null | head -1 || true)
  [ -f "$tf" ] || die "Kein target_files.zip – erst ./noxis.sh build"
  c "APEX-Schlüssel erzeugen"
  apex_keys "$tf"
  mkdir -p "$REL"
  local stamp; stamp=$(date -u +%Y%m%d)
  local name="Noxis-1.0-$stamp-$DEVICE"
  local -a args
  mapfile -t args < <(python3 "$NOXIS/tools/noxis_sign_args.py" "$tf" "$KEYS" args)
  c "Signiere (Apps, APEXe, Verified Boot)"
  sign_target_files_apks "${args[@]}" "$tf" "$REL/$name-target_files.zip"
  c "OTA-Paket"
  ota_from_target_files -k "$KEYS/releasekey" "$REL/$name-target_files.zip" "$REL/$name-ota.zip"
  c "Fastboot-Images"
  img_from_target_files "$REL/$name-target_files.zip" "$REL/$name-img.zip"
  ( cd "$REL" && sha256sum "$name-ota.zip" "$name-img.zip" > "$name.sha256" )
  write_ota_json "$REL/$name-ota.zip" "noxis-$stamp" > "$REL/$DEVICE.json"
  c "Fertig in $REL:"
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

cmd_publish() {  # newest signed OTA → GitHub release + ota/<device>.json (read by the phone's Updater)
  need gh "GitHub CLI installieren und 'gh auth login' ausführen"
  need unzip "unzip installieren"
  local ota desk tag json
  desk="$(desktop_dir)"
  ota=$(ls -t "$desk"/Noxis-*-"$DEVICE"-ota.zip "$REL"/Noxis-*-"$DEVICE"-ota.zip 2>/dev/null | head -n1 || true)
  [ -f "$ota" ] || die "Keine signierte OTA gefunden – erst ./noxis.sh sign"
  [ "$(stat -c %s "$ota")" -lt 2147483648 ] || die "OTA größer als 2 GiB – GitHub-Releases erlauben max. 2 GiB pro Datei"
  unzip -tq "$ota" >/dev/null || die "OTA-Zip beschädigt: $ota"
  unzip -l "$ota" | grep -q "META-INF/com/android/otacert" || die "OTA ohne Signaturzertifikat – mit ./noxis.sh sign erzeugen"
  tag="noxis-$(basename "$ota" | sed -n 's/^Noxis-[0-9.]*-\([0-9]\{8\}\)-.*/\1/p')"
  [ "$tag" != noxis- ] || tag="noxis-$(date -u +%Y%m%d)"
  if gh release view "$tag" -R "$NOXIS_GH_REPO" >/dev/null 2>&1; then tag="$tag-$(date -u +%H%M)"; fi
  ( cd "$(dirname "$ota")" && sha256sum "$(basename "$ota")" ) > "$ota.sha256"
  c "Release $tag ← $(basename "$ota") ($(du -h "$ota" | cut -f1))"
  gh release create "$tag" "$ota" "$ota.sha256" -R "$NOXIS_GH_REPO" \
    --title "Noxis OS ${tag#noxis-}" \
    --notes "Signed OTA for the Nothing Phone (3a) (asteroids). Install: Settings → System → Updater, or adb sideload. SHA-256 in the .sha256 file."
  mkdir -p "$NOXIS/ota"
  json="$NOXIS/ota/$DEVICE.json"
  write_ota_json "$ota" "$tag" > "$json"
  git -C "$NOXIS" add "ota/$DEVICE.json"
  git -C "$NOXIS" commit -qm "OTA: $(basename "$ota")"
  git -C "$NOXIS" push -q origin HEAD
  c "Veröffentlicht. Handy: Einstellungen → System → Updater → Nach Updates suchen"
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
  [ -f "$ota" ] && [ -f "$img" ] || die "Keine fertige ROM in $REL – out/ wird NICHT gelöscht"
  desk=$(desktop_dir); mkdir -p "$desk"
  c "ROM → $desk"
  local f
  for f in "$ota" "$img"; do
    [ "$(dirname "$f")" = "$desk" ] || cp -f "$f" "$desk/"
  done
  for f in "$ota" "$img"; do
    [ "$(sha256sum < "$f")" = "$(sha256sum < "$desk/$(basename "$f")")" ] \
      || die "Kopie von $(basename "$f") fehlerhaft – out/ wird NICHT gelöscht"
  done
  if [ "${NOXIS_KEEP_OUT:-0}" = "1" ]; then
    c "NOXIS_KEEP_OUT=1 – out/ bleibt erhalten"; return 0
  fi
  local o="$SRC/out"
  [ -n "$SRC" ] && [ "$o" = "$SRC/out" ] || die "Unerwarteter out-Pfad: $o"
  [ -d "$o" ] && [ -f "$SRC/build/envsetup.sh" ] || { c "out/ nicht vorhanden"; return 0; }
  c "Lösche $o ($(du -sh "$o" 2>/dev/null | cut -f1))"
  rm -rf -- "$o"
  # signiertes target_files nur für Delta-OTAs nötig – Platz sparen
  rm -f -- "$REL"/Noxis-*-target_files.zip
  c "Belegt jetzt: $(du -sh "$SRC" 2>/dev/null | cut -f1) Quellcode, ccache $(du -sh "${CCACHE_DIR:-$HOME/.cache/ccache}" 2>/dev/null | cut -f1)"
}

# ------------------------------------------------------------ flash
latest() { ls -t "$REL"/Noxis-*-"$1" "$(desktop_dir)"/Noxis-*-"$1" 2>/dev/null | head -1 || true; }

cmd_flash() {
  need fastboot "android-tools installieren"
  need adb "android-tools installieren"
  local img ota
  img=$(latest img.zip); ota=$(latest ota.zip)
  [ -f "$img" ] && [ -f "$ota" ] || die "Erst ./noxis.sh sign"
  cat <<EOF

  Vorbereitung (einmalig):
   1. Nothing OS auf die neueste Version bringen.
   2. Einstellungen → Telefoninfo → 7× Build-Nummer → Entwickleroptionen
      → "OEM-Entsperrung" + "USB-Debugging" an.
   3. adb reboot bootloader  →  fastboot flashing unlock  (LÖSCHT ALLE DATEN)

EOF
  confirm "Ist das Handy entsperrt und im Fastboot-Modus verbunden?" || exit 0
  local prod; prod=$(fastboot getvar product 2>&1 | sed -n 's/^product: *//p')
  # Das Phone (3a) meldet im Bootloader den Qualcomm-Plattformnamen
  # "pineapple" statt "asteroids" - beides ist richtig.
  case "${prod,,}" in
    *asteroids*|pineapple) c "Gerät: $prod (Nothing Phone (3a))" ;;
    *) confirm "Gerät meldet '$prod' statt Asteroids/pineapple. Trotzdem weiter?" || exit 1 ;;
  esac
  local tmp; tmp=$(mktemp -d)
  unzip -q -o "$img" -d "$tmp"
  # recovery gehoert dazu: das Phone (3a) hat eine eigene Recovery-Partition.
  # Ohne sie startet gleich die Nothing-Recovery, und die nimmt das
  # Noxis-Paket nicht an.
  for p in boot init_boot vendor_boot recovery dtbo vbmeta vbmeta_system vbmeta_vendor; do
    # Ausdruecklich in beide Slots: der Nothing-Bootloader meldet fuer
    # init_boot/recovery/... kein has-slot, dann haengt fastboot kein _a an
    # und die Recovery landet nicht im aktiven Slot.
    [ -f "$tmp/$p.img" ] || continue
    local n=0
    for sl in a b; do
      c "flash ${p}_$sl"
      fastboot flash "${p}_$sl" "$tmp/$p.img" && n=$((n+1)) || warn "${p}_$sl gibt es nicht"
    done
    # Partition ohne Slots (z.B. vbmeta auf manchen Geraeten): ohne Endung
    [ "$n" -gt 0 ] || { c "flash $p"; fastboot flash "$p" "$tmp/$p.img" || die "$p liess sich nicht flashen"; }
  done
  rm -rf "$tmp"
  fastboot reboot recovery
  cat <<EOF

  Im Noxis-Recovery:
   1. "Factory reset" → "Format data / factory reset" → bestätigen
   2. Zurück → "Apply update" → "Apply from ADB"

EOF
  read -rp "Wenn 'Apply from ADB' aktiv ist, Enter drücken … " _
  adb sideload "$ota" || warn "Fortschritt 47% mit 'Fehler' ist bei sideload normal"
  cat <<EOF

  Im Recovery: "Reboot system now" – erster Start dauert 5–10 Minuten.

  Danach:
   0. Falls beim Bauen Apps "nach dem Flashen" gemeldet wurden:
      USB-Debugging an, dann am PC: ./noxis.sh nachinstall
   1. KernelSU-App öffnen → zeigt "Funktioniert" + Kernel-Version.
   2. Root ist für ALLE Apps gesperrt. Freigabe nur einzeln:
      KernelSU → Superuser → App antippen → Root erlauben.
   3. Mullvad öffnen, anmelden – vorher gibt es kein Internet (Killswitch).
   4. Bootloader BLEIBT offen – NICHT "fastboot flashing lock" ausführen,
      das macht das Gerät mit Noxis OS unbootbar.

EOF
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
  nachinstall) cmd_nachinstall ;;
  publish) cmd_publish ;;
  cleanup) cmd_cleanup ;;
  all)    shift; cmd_all "$@" ;;
  *) sed -n '2,17p' "$0" ;;
esac
