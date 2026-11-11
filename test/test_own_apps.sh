#!/usr/bin/env bash
# Tests for the own-apps step of noxis.sh: download, SHA-256 check, Android.bp, overrides, product config.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok()  { echo "  ✓ $*"; pass=$((pass + 1)); }
bad() { echo "  ✗ $*"; fail=$((fail + 1)); }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

REL="$T/release"; mkdir -p "$REL"
for a in NoxisCalendar NoxisClock NoxisCalculator NoxisNotes NoxisCall NoxisBattery; do
  head -c 4096 /dev/urandom > "$REL/$a.apk"
  echo "$a Real3rr0r303YT/${a/Noxis/Nothing} 0123abcd" >> "$REL/SOURCES"
done
( cd "$REL" && sha256sum *.apk > SHA256SUMS )
echo tampered >> "$REL/NoxisBattery.apk"        # checksum no longer matches

fn=$(sed -n '/^NOXIS_APPS_REPO=/,/^cmd_apps() {/p' "$ROOT/noxis.sh" | sed '$d')
run() {
  NOXIS="$T/noxis" NOXIS_APPS_URL="$1" bash -c "c(){ echo \"[c] \$*\"; }; warn(){ echo \"[w] \$*\"; }; $fn
install_own_apps"
}
mkdir -p "$T/noxis"
out=$(run "file://$REL")
P="$T/noxis/vendor/noxis/prebuilt"
for a in NoxisCalendar NoxisClock NoxisCalculator NoxisNotes NoxisCall; do
  [ -f "$P/$a/$a.apk" ] && cmp -s "$P/$a/$a.apk" "$REL/$a.apk" && ok "$a downloaded and verified" || bad "$a missing"
done
[ ! -e "$P/NoxisBattery/NoxisBattery.apk" ] && grep -q "NoxisBattery: SHA-256 MISMATCH" <<<"$out" && ok "tampered APK rejected (SHA-256)" || bad "tampered APK accepted"
grep -q 'overrides: \["Etar"\]' "$P/NoxisCalendar/Android.bp" && ok "calendar replaces Etar" || bad "Etar override"
grep -q 'overrides: \["DeskClock"\]' "$P/NoxisClock/Android.bp" && ok "clock replaces DeskClock" || bad "DeskClock override"
grep -q 'overrides: \["ExactCalculator"\]' "$P/NoxisCalculator/Android.bp" && ok "calculator replaces ExactCalculator" || bad "calculator override"
! grep -q overrides "$P/NoxisCall/Android.bp" && ok "phone app added, stock Dialer kept (emergency calls)" || bad "dialer overridden"
grep -q "presigned: false" "$P/NoxisNotes/Android.bp" && ok "apps re-signed with the ROM key" || bad "presigned"
grep -q "0123abcd" "$P/NoxisNotes/SOURCE" && ok "source commit recorded" || bad "SOURCE"
python3 - "$P" <<'PY' && ok "Android.bp files well-formed" || bad "Android.bp syntax"
import sys, glob, re
for f in glob.glob(sys.argv[1] + "/*/Android.bp"):
    t = open(f).read()
    assert t.count("{") == t.count("}") and t.count("[") == t.count("]") and re.search(r'name: "Noxis\w+"', t), f
PY
out=$(run "file://$T/nothing-here")
grep -q "release not found" <<<"$out" && [ "$(ls "$P" | wc -l)" = 5 ] && ok "missing release → warning, build continues" || bad "missing release: $out"
mk="$ROOT/vendor/noxis/config/noxis.mk"
grep -q "NOXIS_OWN_APPS := NoxisCalendar NoxisClock NoxisCalculator NoxisNotes NoxisCall NoxisBattery" "$mk" && grep -q 'wildcard $(NOXIS_PATH)/prebuilt/$(a)/$(a).apk' "$mk" && ok "product config adds only downloaded apps" || bad "noxis.mk"
wf="$ROOT/.github/workflows/noxis-apps.yml"
python3 -c "import yaml; yaml.safe_load(open('$wf'))" 2>/dev/null && ok "workflow YAML valid" || bad "workflow yaml"
for r in NothingCalendar NothingClock NothingNotes Calculator NothingCall NothingBattery; do grep -q "repo: Real3rr0r303YT/$r " "$wf" || { bad "workflow lacks $r"; continue; }; done; ok "workflow builds all 6 repos"
echo; echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
