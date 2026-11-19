#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Noxis OS – Copyright (C) 2026 3rr0r (Real3rr0r303YT) – Made by 3rr0r303YT on TikTok
#
# Overlay hotfix without a full build: compiles Noxis overlays (RROs) from
# vendor/noxis/overlay with the aapt2 that ships in the source tree, signs them
# with your platform key (same certificate as in the image) and puts them on
# the phone as a KernelSU module that mounts them over the built-in ones.
# Takes a minute instead of hours. The next normal build contains the same
# overlays, then remove the module again (KernelSU app → Modules).
#
#   tools/noxis_rro_hotfix.sh <noxis-dir> <src-dir> <keys-dir> [OverlayName ...]
set -euo pipefail
NOXIS="$1"; SRC="$2"; KEYS="$3"; shift 3
names=("$@"); [ ${#names[@]} -gt 0 ] || names=(NoxisUpdaterOverlay)

c()    { printf '\033[38;5;111m[hotfix]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

find_tool() {  # <name> → first match in the source tree prebuilts
  local f
  f=$(find "$SRC/prebuilts/sdk/tools" "$SRC/prebuilts/build-tools" -name "$1" -type f 2>/dev/null \
      | grep -E '/linux(-x86)?/' | head -n1 || true)
  [ -n "$f" ] || f=$(command -v "$1" 2>/dev/null || true)
  echo "$f"
}

AAPT2=$(find_tool aapt2)
[ -x "$AAPT2" ] || die "aapt2 not found in $SRC/prebuilts – is the source tree synced?"
APKSIGNER_JAR=$(find "$SRC/prebuilts/sdk/tools" -name apksigner.jar -type f 2>/dev/null | head -n1 || true)
APKSIGNER=$(command -v apksigner 2>/dev/null || true)
JAVA=$(find "$SRC/prebuilts/jdk" -path '*linux-x86/bin/java' -type f 2>/dev/null | sort -r | head -n1 || true)
[ -n "$JAVA" ] || JAVA=$(command -v java || true)
if [ -z "$APKSIGNER" ]; then
  [ -n "$APKSIGNER_JAR" ] && [ -x "$JAVA" ] || die "apksigner not found (neither in prebuilts nor installed: emerge dev-util/android-sdk-build-tools)"
  APKSIGNER="$JAVA -jar $APKSIGNER_JAR"
fi
ANDROID_JAR=$(ls -d "$SRC"/prebuilts/sdk/[0-9]*/public/android.jar 2>/dev/null | sort -V | tail -n1 || true)
[ -f "$ANDROID_JAR" ] || ANDROID_JAR="$SRC/prebuilts/sdk/current/public/android.jar"
[ -f "$ANDROID_JAR" ] || die "android.jar not found in $SRC/prebuilts/sdk"
[ -f "$KEYS/platform.pk8" ] && [ -f "$KEYS/platform.x509.pem" ] || die "No platform key in $KEYS"
command -v adb >/dev/null || die "adb missing"
c "aapt2: $AAPT2"
c "android.jar: $ANDROID_JAR"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mod="$work/module"; mkdir -p "$mod"
cat > "$mod/module.prop" <<EOF
id=noxis_overlay_hotfix
name=Noxis overlay hotfix
version=$(date -u +%Y%m%d-%H%M)
versionCode=$(date -u +%s)
author=Real3rr0r303YT
description=Newer Noxis overlays ($(IFS=,; echo "${names[*]}")) until the next build. Remove after updating. Made by 3rr0r303YT on TikTok (GPL-3.0)
EOF

adb wait-for-device
for n in "${names[@]}"; do
  dir="$NOXIS/vendor/noxis/overlay/$n"
  [ -f "$dir/AndroidManifest.xml" ] || die "No overlay $n in vendor/noxis/overlay"
  pkg=$(sed -n 's/.*package="\([^"]*\)".*/\1/p' "$dir/AndroidManifest.xml" | head -n1)
  path=$(adb shell pm path "$pkg" 2>/dev/null | sed -n 's/^package://p' | tr -d '\r' | head -n1)
  [ -n "$path" ] || die "$pkg is not on the phone – this hotfix only replaces overlays that are already built in"
  c "$n ($pkg) → $path"
  mkdir -p "$work/$n"
  "$AAPT2" compile --dir "$dir/res" -o "$work/$n/res.zip"
  "$AAPT2" link -o "$work/$n/unaligned.apk" --manifest "$dir/AndroidManifest.xml" \
    -I "$ANDROID_JAR" --min-sdk-version 34 --target-sdk-version 37 \
    --no-resource-removal "$work/$n/res.zip"
  # Android 11+ wants resources.arsc stored and 4-byte aligned
  python3 - "$work/$n/unaligned.apk" "$work/$n/aligned.apk" <<'PY'
import sys, zipfile
src, dst = sys.argv[1:3]
with zipfile.ZipFile(src) as zi, open(dst, "wb") as raw:
    zo = zipfile.ZipFile(raw, "w")
    for info in zi.infolist():
        data = zi.read(info.filename)
        ni = zipfile.ZipInfo(info.filename, date_time=info.date_time)
        ni.external_attr = info.external_attr
        store = info.filename == "resources.arsc" or info.filename.endswith(".png")
        ni.compress_type = zipfile.ZIP_STORED if store else zipfile.ZIP_DEFLATED
        if store:
            # local header = 30 bytes + name + extra; pad extra so data starts on 4 bytes
            off = raw.tell() + 30 + len(info.filename.encode())
            ni.extra = b"\0" * ((4 - off % 4) % 4)
        zo.writestr(ni, data)
    zo.close()
PY
  $APKSIGNER sign --key "$KEYS/platform.pk8" --cert "$KEYS/platform.x509.pem" \
    --out "$work/$n/$n.apk" "$work/$n/aligned.apk"
  # KernelSU mounts module/system/... over /system; system_ext and product sit below it
  case "$path" in
    /system/*) dest="$mod$path" ;;
    *)         dest="$mod/system$path" ;;
  esac
  mkdir -p "$(dirname "$dest")"
  cp "$work/$n/$n.apk" "$dest"
done

zip_out="$NOXIS/postinstall/modules/NoxisOverlayHotfix.zip"
mkdir -p "$(dirname "$zip_out")"
rm -f "$zip_out"
( cd "$mod" && zip -qr9 "$zip_out" . )
adb push "$zip_out" /sdcard/Download/NoxisOverlayHotfix.zip >/dev/null
adb shell "su -c '/data/adb/ksud module install /sdcard/Download/NoxisOverlayHotfix.zip'" \
  || die "Install failed – KernelSU app → Superuser → allow Shell, then run again"
# the quick string/colour overlays made by hand earlier are no longer needed
adb shell "su -c 'for o in \$(cmd overlay list | grep -o \"com.android.shell:noxis_[a-z0-9]*\"); do cmd overlay disable --user 0 \$o; done'" >/dev/null 2>&1 || true
c "Done – reboot the phone (adb reboot). Remove the module after the next Noxis update."
