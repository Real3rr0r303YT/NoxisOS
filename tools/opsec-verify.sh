#!/usr/bin/env bash
# ============================================================
#  Noxis OS – OPSEC-Prüfung des fertigen Builds
#
#  Prüft am gebauten Image, nicht an der Konfiguration: was in den
#  Makefiles steht, ist eine Absicht, was im Image liegt, ist die Tatsache.
#  Die Gerätebäume kommen von fremden Projekten und werden dort laufend
#  geändert - ein Build, der plötzlich Google-Dienste mitbringt, soll
#  auffallen, bevor er aufs Handy kommt.
#
#    ./tools/opsec-verify.sh <pfad-zu-out/target/product/asteroids>
#
#  Rückgabe 0 = sauber, 1 = Regelverstoß, 2 = nicht prüfbar
# ============================================================
set -uo pipefail

PROD="${1:-}"
fail=0
checked=0

c()    { printf '\033[38;5;111m[opsec]\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; checked=$((checked+1)); }
bad()  { printf '  \033[31mVERSTOSS\033[0m %s\n' "$*"; fail=$((fail+1)); checked=$((checked+1)); }
warn() { printf '  \033[33mhinweis\033[0m %s\n' "$*"; }

[ -n "$PROD" ] || { echo "Aufruf: $0 <out/target/product/asteroids>"; exit 2; }
[ -d "$PROD" ] || { echo "[opsec] $PROD gibt es nicht"; exit 2; }

# Wo liegen die APKs und Props? Je nach Build-Stand entpackt oder als Image.
SYS="$PROD/system"
[ -d "$SYS/system" ] && SYS="$SYS/system"
if [ ! -d "$SYS" ]; then
  echo "[opsec] $PROD/system fehlt - erst bauen, dann prüfen"
  exit 2
fi

# ---------------------------------------------------------------- 1. keine Google-Dienste
c "Google-Dienste"
# Die Paketnamen, die tatsächlich Dienste mitbringen. Reine AOSP-Dateien mit
# "google" im Namen (Codec-Konfigurationen) sind kein Verstoß und stehen
# bewusst nicht in dieser Liste.
GMS_APKS="GmsCore GoogleServicesFramework Phonesky PrebuiltGmsCore GoogleLoginService
          SetupWizard GoogleCalendarSyncAdapter GoogleContactsSyncAdapter FaceLock
          GooglePartnerSetup GoogleExtServices GoogleFeedback"
found=""
for n in $GMS_APKS; do
  if find "$SYS" -iname "${n}*.apk" -print -quit 2>/dev/null | grep -q .; then
    found="$found $n"
  fi
done
if [ -n "$found" ]; then bad "Google-Pakete im Image:$found"
else ok "keine Google-Dienste im Image"; fi

# ---------------------------------------------------------------- 2. OPSEC-Apps vorhanden
c "OPSEC-Apps"
want_any() {   # $1 = Beschreibung, Rest = mögliche APK-Namen
  local label="$1"; shift
  for n in "$@"; do
    if find "$SYS" -iname "${n}*.apk" -print -quit 2>/dev/null | grep -q .; then
      ok "$label ($n)"; return 0
    fi
  done
  warn "$label fehlt - mit ./noxis.sh apps holen"
  return 1
}
want_any "VPN"            MullvadVPN Mullvad
want_any "Tor"            TorBrowser Tor
want_any "Browser"        Fennec Cromite
want_any "Kamera"         GrapheneCamera Camera
want_any "Noxis Guard"    NoxisGuard

# ---------------------------------------------------------------- 3. Bootloader bleibt offen
c "Bootloader"
# Ein ROM, das sich mit eigenen AVB-Schlüsseln wieder verriegeln lässt, sperrt
# den Nutzer aus, sobald ein Update schiefgeht. Das soll hier nicht passieren.
if grep -rqs "ro.boot.flash.locked=1" "$PROD"/*.prop "$SYS"/build.prop \
      "$SYS"/etc/prop.default 2>/dev/null; then
  bad "Build erzwingt verriegelten Bootloader"
else
  ok "Bootloader bleibt entsperrbar"
fi

# ---------------------------------------------------------------- 4. kein Play-Integrity-Spoofing
c "Integrity"
if grep -rqsiE "PlayIntegrityFix|keybox\.xml|ro\.spoof\." "$SYS" 2>/dev/null; then
  bad "Play-Integrity-Spoofing gefunden - nicht Teil von Noxis OS"
else
  ok "kein Integrity-Spoofing"
fi

# ---------------------------------------------------------------- 5. Updates kommen von uns
c "Updater"
PROPS=$(find "$PROD" "$SYS" -maxdepth 2 -name "build.prop" -o -maxdepth 2 -name "*.prop" 2>/dev/null)
if [ -n "$PROPS" ] && grep -hqs "lineage.updater.uri=.*Real3rr0r303YT" $PROPS 2>/dev/null; then
  ok "Updater zeigt auf das eigene GitHub-Release"
elif [ -n "$PROPS" ] && grep -hqs "lineage.updater.uri=" $PROPS 2>/dev/null; then
  bad "Updater zeigt auf fremde Server: $(grep -hs 'lineage.updater.uri=' $PROPS | head -1)"
else
  warn "keine Updater-URI gefunden"
fi

# ---------------------------------------------------------------- Ergebnis
echo
if [ "$fail" -gt 0 ]; then
  c "$fail von $checked Prüfungen verletzt - dieser Build sollte nicht aufs Handy"
  exit 1
fi
c "$checked Prüfungen bestanden - Build entspricht den OPSEC-Regeln"
exit 0
