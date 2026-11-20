#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Noxis OS – Made by 3rr0r303YT on TikTok
# ============================================================
#  Noxis OS – OPSEC check of the finished build
#
#  Checks the built image, not the configuration: what the makefiles say is
#  an intention, what is in the image is the fact. The device trees come
#  from other projects and change all the time - a build that suddenly
#  brings Google services should be noticed before it reaches the phone.
#
#    ./tools/opsec-verify.sh <path-to-out/target/product/asteroids>
#
#  Exit 0 = clean, 1 = rule violation, 2 = cannot be checked
# ============================================================
set -uo pipefail

PROD="${1:-}"
fail=0
checked=0

c()    { printf '\033[38;5;111m[opsec]\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; checked=$((checked+1)); }
bad()  { printf '  \033[31mVIOLATION\033[0m %s\n' "$*"; fail=$((fail+1)); checked=$((checked+1)); }
warn() { printf '  \033[33mnote\033[0m  %s\n' "$*"; }

[ -n "$PROD" ] || { echo "Usage: $0 <out/target/product/asteroids>"; exit 2; }
[ -d "$PROD" ] || { echo "[opsec] $PROD does not exist"; exit 2; }

# Where are the APKs and props? Extracted or as an image, depending on the build.
SYS="$PROD/system"
[ -d "$SYS/system" ] && SYS="$SYS/system"
if [ ! -d "$SYS" ]; then
  echo "[opsec] $PROD/system is missing - build first, then check"
  exit 2
fi
# Apps and props are not only in system/: Noxis apps are product_specific
# (product/), Noxis Guard is system_ext. Check all partitions - also so
# Google services cannot slip into product/ unnoticed.
ALL="$SYS"
for p in system_ext product vendor odm; do
  [ -d "$PROD/$p" ] && ALL="$ALL $PROD/$p"
done
POST="${NOXIS_POSTINSTALL:-${NOXIS_NACH:-/nonexistent}}"

# ---------------------------------------------------------------- 1. no Google services
c "Google services"
# The package names that really bring services. Plain AOSP files with
# "google" in the name (codec configs) are no violation and are not on this
# list on purpose.
GMS_APKS="GmsCore GoogleServicesFramework Phonesky PrebuiltGmsCore GoogleLoginService
          SetupWizard GoogleCalendarSyncAdapter GoogleContactsSyncAdapter FaceLock
          GooglePartnerSetup GoogleExtServices GoogleFeedback"
found=""
for n in $GMS_APKS; do
  if find $ALL -iname "${n}*.apk" -print -quit 2>/dev/null | grep -q .; then
    found="$found $n"
  fi
done
if [ -n "$found" ]; then bad "Google packages in the image:$found"
else ok "no Google services in the image"; fi

# ---------------------------------------------------------------- 2. OPSEC apps present
c "OPSEC apps"
want_any() {   # $1 = description, rest = possible APK names
  local label="$1"; shift
  for n in "$@"; do
    if find $ALL -iname "${n}*.apk" -print -quit 2>/dev/null | grep -q .; then
      ok "$label ($n)"; return 0
    fi
  done
  for n in "$@"; do
    [ -f "$POST/$n.apk" ] && { warn "$label ($n) is installed after flashing (./noxis.sh postinstall)"; return 0; }
  done
  warn "$label missing - get it with ./noxis.sh apps"
  return 1
}
want_any "VPN"            MullvadVPN Mullvad
want_any "Tor"            TorBrowser Tor
want_any "Browser"        IronFox
want_any "Camera"         NoxisCamera GrapheneCamera Camera
want_any "Noxis Guard"    NoxisGuard
# No root in Noxis: no KernelSU manager, no KernelSU in the kernel, no su
if [ -n "$(find "$PROD" -iname 'KernelSU*.apk' 2>/dev/null | head -1)" ]; then
  bad "KernelSU manager in the image (Noxis has no root)"
elif [ -f "$PROD/kernel" ] && LC_ALL=C grep -aq "KernelSU" "$PROD/kernel"; then
  bad "Kernel contains KernelSU (Noxis has no root)"
elif [ -e "$SYS/xbin/su" ] || [ -e "$SYS/bin/su" ]; then
  bad "su binary in the image (Noxis has no root)"
else
  ok "No root – no KernelSU, no su"
fi

# ---------------------------------------------------------------- 3. bootloader stays unlockable
c "Bootloader"
# A ROM that relocks itself with its own AVB keys locks the user out as soon
# as an update goes wrong. That must not happen here.
if grep -rqs "ro.boot.flash.locked=1" "$PROD"/*.prop "$SYS"/build.prop \
      "$SYS"/etc/prop.default 2>/dev/null; then
  bad "The build forces a locked bootloader"
else
  ok "Bootloader stays unlockable"
fi

# ---------------------------------------------------------------- 4. no Play Integrity spoofing
c "Integrity"
if grep -rqsiE "PlayIntegrityFix|keybox\.xml|ro\.spoof\." $ALL 2>/dev/null; then
  bad "Play Integrity spoofing found - not part of Noxis OS"
else
  ok "no integrity spoofing"
fi

# ---------------------------------------------------------------- 5. updates come from us
c "Updater"
PROPS=$( { find "$PROD" -maxdepth 1 -name "*.prop"; find $ALL -maxdepth 3 -name "*.prop"; } 2>/dev/null)
if [ -n "$PROPS" ] && grep -hqs "lineage.updater.uri=.*Real3rr0r303YT" $PROPS 2>/dev/null; then
  ok "Updater points to our own GitHub release"
elif [ -n "$PROPS" ] && grep -hqs "lineage.updater.uri=" $PROPS 2>/dev/null; then
  bad "Updater points to foreign servers: $(grep -hs 'lineage.updater.uri=' $PROPS | head -1)"
else
  warn "no Updater URI found"
fi

# ---------------------------------------------------------------- 6. ADB only with approval
c "ADB"
if [ -n "$PROPS" ] && grep -hqs "^ro.adb.secure=0" $PROPS 2>/dev/null; then
  if [ "${NOXIS_DEBUG:-0}" = 1 ]; then
    warn "DEBUG build: ADB without approval - for debugging only, not for daily use"
  else
    bad "ADB without approval (ro.adb.secure=0) - anyone with a USB cable has access"
  fi
else
  ok "ADB only with the approval dialog"
fi

# ---------------------------------------------------------------- result
echo
if [ "$fail" -gt 0 ]; then
  c "$fail of $checked checks violated - this build should not go onto a phone"
  exit 1
fi
c "$checked checks passed - the build follows the OPSEC rules"
exit 0
