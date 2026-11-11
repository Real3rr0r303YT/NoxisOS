#!/usr/bin/env bash
# ============================================================
#  Noxis OS – Build-Werkzeug (Android 17 / LineageOS 24.0)
#  Gerät: Nothing Phone (3a) / (3a) Pro  –  "asteroids"
#
#  ./noxis.sh check              Rechner prüfen (RAM, Platte, Tools)
#  ./noxis.sh sync               Quellcode holen (--depth=1, ~110 GB) + Noxis einbinden
#  ./noxis.sh apps               Kamera/PDF, Firefox (Fennec), Mullvad, Tor, KernelSU-Manager
#  ./noxis.sh blobs <ota.zip>    Herstellerdateien aus Nothing-OS-OTA ziehen
#  ./noxis.sh keys               Eigene Signaturschlüssel
#  ./noxis.sh build              Kompilieren (user-Build, KernelSU im Kernel)
#  ./noxis.sh sign               Signieren → OTA + Images → Desktop, out/ löschen
#  ./noxis.sh cleanup            ROM auf den Desktop, out/ löschen (NOXIS_KEEP_OUT=1 behält)
#  ./noxis.sh flash              Aufs Handy installieren (geführt, Bootloader bleibt offen)
#  ./noxis.sh publish            OTA als GitHub-Release hochladen → Handy: Einstellungen → System → Updater
#  ./noxis.sh all <ota.zip>      sync → apps → blobs → keys → build → sign
# ============================================================
set -euo pipefail

NOXIS="$(cd "$(dirname "$0")" && pwd)"
SRC="${NOXIS_SRC:-$HOME/noxis-src}"
KEYS="${NOXIS_KEYS:-$HOME/.noxis-keys}"
OUT="${NOXIS_OUT:-$NOXIS/release}"
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
  set +u
  # shellcheck disable=SC1091
  source build/envsetup.sh >/dev/null
  breakfast "$DEVICE" "$VARIANT" >/dev/null || die "breakfast $DEVICE $VARIANT fehlgeschlagen"
  set -u
}

# ------------------------------------------------------------ check
cmd_check() {
  local ram disk
  ram=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
  disk=$(df -BG --output=avail "$(dirname "$SRC")" | tail -1 | tr -dc 0-9)
  c "RAM: ${ram} GB (empfohlen 32+, mit 16 GB nur mit 32 GB Swap)"
  c "Freier Platz bei $(dirname "$SRC"): ${disk} GB (nötig ~400 GB)"
  [ "$ram" -lt 16 ] && warn "Zu wenig RAM für einen Android-Build"
  [ "$disk" -lt 350 ] && warn "Zu wenig Platz"
  for t in git git-lfs python3 curl zip unzip openssl ccache fastboot adb; do
    command -v "$t" >/dev/null && echo "  ✓ $t" || echo "  ✗ $t"
  done
  command -v repo >/dev/null && echo "  ✓ repo" || echo "  ✗ repo  →  curl -o ~/.local/bin/repo https://storage.googleapis.com/git-repo-downloads/repo && chmod +x ~/.local/bin/repo"
  cat <<'EOF'

Pakete:
  Gentoo:  emerge -av dev-vcs/git dev-vcs/git-lfs dev-util/ccache app-arch/zip app-arch/unzip \
           dev-lang/python sys-devel/bc sys-devel/bison sys-devel/flex dev-libs/openssl \
           app-arch/lz4 dev-util/android-tools sys-libs/ncurses media-gfx/imagemagick
  Ubuntu:  sudo apt install bc bison build-essential ccache curl flex g++-multilib gcc-multilib git \
           git-lfs gnupg gperf imagemagick lib32readline-dev lib32z1-dev libelf-dev liblz4-tool \
           lz4 libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool \
           squashfs-tools xsltproc zip zlib1g-dev python3 android-sdk-libsparse-utils
EOF
}

# ------------------------------------------------------------ sync
cmd_sync() {
  need repo "siehe ./noxis.sh check"
  need git-lfs "git-lfs installieren"
  mkdir -p "$SRC" && cd "$SRC"
  if [ ! -d .repo ]; then
    c "LineageOS $BRANCH initialisieren"
    repo init -u https://github.com/LineageOS/android.git -b "$BRANCH" --git-lfs --no-clone-bundle --depth=1
  fi
  mkdir -p .repo/local_manifests
  cp "$NOXIS/manifest/noxis.xml" .repo/local_manifests/noxis.xml
  c "Quellcode synchronisieren (beim ersten Mal mehrere Stunden)"
  repo sync -c --current-branch --depth=1 -j"$(nproc)" --force-sync --no-clone-bundle --no-tags --optimized-fetch --prune \
    || repo sync -c --current-branch --depth=1 -j4 --force-sync --no-clone-bundle --no-tags
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
  ver=$(curl -fsSL https://dist.torproject.org/torbrowser/ | grep -oE 'href="[0-9]+\.[0-9]+(\.[0-9]+)?/"' \
        | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | sort -V | tail -1) || true
  [ -n "$ver" ] && echo "https://dist.torproject.org/torbrowser/$ver/tor-browser-android-aarch64-$ver.apk"
  return 0
}

install_fennec() {  # Firefox ohne Google/Telemetrie (Fennec F-Droid), arm64-Variante
  local api ver codes code dir="$NOXIS/vendor/noxis/prebuilt/Fennec"
  api=$(curl -fsSL https://f-droid.org/api/v1/packages/org.mozilla.fennec_fdroid) || { warn "Fennec: F-Droid nicht erreichbar"; return 0; }
  ver=$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); s=d["suggestedVersionCode"]; print(next(p["versionName"] for p in d["packages"] if p["versionCode"]==s))' "$api")
  codes=$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(" ".join(str(p["versionCode"]) for p in d["packages"] if p["versionName"]==sys.argv[2]))' "$api" "$ver")
  mkdir -p "$dir"
  for code in $codes; do
    curl -fsSL -o "$dir/Fennec.apk.part" "https://f-droid.org/repo/org.mozilla.fennec_fdroid_$code.apk" || continue
    if unzip -l "$dir/Fennec.apk.part" 2>/dev/null | grep -q 'lib/arm64-v8a/'; then
      mv "$dir/Fennec.apk.part" "$dir/Fennec.apk"
      c "Fennec ← F-Droid $ver ($code, arm64-v8a)"
      cat > "$dir/Android.bp" <<'EOF'
android_app_import {
    name: "Fennec",
    apk: "Fennec.apk",
    presigned: true,
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
  if ! curl -fL --progress-bar -o "$dir/$name.apk.part" "$url"; then
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
      echo "    // re-signed with the Noxis release key at sign time (noxis.sh sign)"
      echo "    presigned: false,"
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
  ota="$(cd "$(dirname "$ota")" && pwd)/$(basename "$ota")"
  local want
  want=$(sed -n 's/^## .*are from the \(.*\) release.*/\1/p' "$SRC/device/nothing/$DEVICE/proprietary-files.txt" | head -1)
  [ -n "$want" ] && c "Gerätebaum erwartet Nothing OS: $want"
  cd "$SRC/device/nothing/$DEVICE"
  c "Herstellerdateien extrahieren (WLAN, Mobilfunk/IMS, NFC, eSIM, Kamera, Firmware)"
  ./extract-files.py "$ota"
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
  cmd_vendor
  envsetup
  export USE_CCACHE=1 CCACHE_EXEC="$(command -v ccache || true)"
  [ -n "$CCACHE_EXEC" ] && ccache -M "${NOXIS_CCACHE_SIZE:-25G}" >/dev/null
  c "Baue Noxis OS ($DEVICE-$VARIANT) – das dauert"
  mka target-files-package otatools
  c "Build fertig. Weiter: ./noxis.sh sign"
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
  mkdir -p "$OUT"
  local stamp; stamp=$(date -u +%Y%m%d)
  local name="Noxis-1.0-$stamp-$DEVICE"
  local -a args
  mapfile -t args < <(python3 "$NOXIS/tools/noxis_sign_args.py" "$tf" "$KEYS" args)
  c "Signiere (Apps, APEXe, Verified Boot)"
  sign_target_files_apks "${args[@]}" "$tf" "$OUT/$name-target_files.zip"
  c "OTA-Paket"
  ota_from_target_files -k "$KEYS/releasekey" "$OUT/$name-target_files.zip" "$OUT/$name-ota.zip"
  c "Fastboot-Images"
  img_from_target_files "$OUT/$name-target_files.zip" "$OUT/$name-img.zip"
  ( cd "$OUT" && sha256sum "$name-ota.zip" "$name-img.zip" > "$name.sha256" )
  write_ota_json "$OUT/$name-ota.zip" "noxis-$stamp" > "$OUT/$DEVICE.json"
  c "Fertig in $OUT:"
  ls -1 "$OUT" | sed 's,^,  ,'
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
  ota=$(ls -t "$desk"/Noxis-*-"$DEVICE"-ota.zip "$OUT"/Noxis-*-"$DEVICE"-ota.zip 2>/dev/null | head -n1 || true)
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
  [ -f "$ota" ] && [ -f "$img" ] || die "Keine fertige ROM in $OUT – out/ wird NICHT gelöscht"
  desk=$(desktop_dir); mkdir -p "$desk"
  c "ROM → $desk"
  cp -f "$ota" "$img" "$desk/"
  local f
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
  rm -f -- "$OUT"/Noxis-*-target_files.zip
  c "Belegt jetzt: $(du -sh "$SRC" 2>/dev/null | cut -f1) Quellcode, ccache $(du -sh "${CCACHE_DIR:-$HOME/.cache/ccache}" 2>/dev/null | cut -f1)"
}

# ------------------------------------------------------------ flash
latest() { ls -t "$OUT"/Noxis-*-"$1" 2>/dev/null | head -1 || true; }

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
  [[ "${prod,,}" == *asteroids* ]] || confirm "Gerät meldet '$prod' statt Asteroids. Trotzdem weiter?" || exit 1
  local tmp; tmp=$(mktemp -d)
  unzip -q -o "$img" -d "$tmp"
  for p in boot init_boot vendor_boot dtbo vbmeta vbmeta_system vbmeta_vendor; do
    [ -f "$tmp/$p.img" ] && { c "flash $p"; fastboot flash "$p" "$tmp/$p.img"; }
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
  sync)   cmd_sync ;;
  vendor) cmd_vendor ;;
  apps)   cmd_apps ;;
  blobs)  shift; cmd_blobs "$@" ;;
  keys)   cmd_keys ;;
  build)  cmd_build ;;
  sign)   cmd_sign ;;
  flash)  cmd_flash ;;
  publish) cmd_publish ;;
  cleanup) cmd_cleanup ;;
  all)    shift; cmd_all "$@" ;;
  *) sed -n '2,17p' "$0" ;;
esac
