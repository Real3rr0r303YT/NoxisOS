#!/usr/bin/env bash
# Tests for ./noxis.sh publish: Updater JSON, GitHub release call, checks against bad OTAs.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok()  { echo "  ✓ $*"; pass=$((pass + 1)); }
bad() { echo "  ✗ $*"; fail=$((fail + 1)); }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

mkota() {  # <file> <with cert 0|1>
  python3 - "$1" "$2" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1], "w")
z.writestr("META-INF/com/android/metadata", "ota-type=AB\npost-timestamp=1790000000\npre-device=asteroids\n")
if sys.argv[2] == "1":
    z.writestr("META-INF/com/android/otacert", "-----BEGIN CERTIFICATE-----\nx\n-----END CERTIFICATE-----\n")
z.writestr("payload.bin", b"\0" * 1024)
z.close()
PY
}
block=$(sed -n '/^# -* OTA updates over GitHub/,/^# -* cleanup/p' "$ROOT/noxis.sh" | sed '$d')
REPO="$T/repo"; git init -q -b main "$REPO"; git -C "$REPO" commit -q --allow-empty -m init
git init -q --bare -b main "$T/remote.git"; git -C "$REPO" remote add origin "$T/remote.git"; git -C "$REPO" push -q origin HEAD:main 2>/dev/null; git -C "$REPO" branch -q -u origin/main 2>/dev/null || true
mkdir -p "$T/bin" "$T/desk" "$T/out"
cat > "$T/bin/gh" <<SH
#!/bin/sh
echo "gh \$*" >> "$T/gh.log"
[ "\$1 \$2" = "release view" ] && [ -f "$T/existing" ] && exit 0
[ "\$1 \$2" = "release view" ] && exit 1
exit 0
SH
chmod 755 "$T/bin/gh"
run() {
  PATH="$T/bin:$PATH" bash -c "set -euo pipefail
c(){ echo \"[c] \$*\"; }; die(){ echo \"[die] \$*\"; exit 1; }; need(){ command -v \"\$1\" >/dev/null || die \"\$1 fehlt\"; }
desktop_dir(){ echo '$T/desk'; }
NOXIS='$REPO'; OUT='$T/out'; DEVICE=asteroids
$block
cmd_publish" 2>&1
}
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t

out=$(run); grep -q "Keine signierte OTA" <<<"$out" && ok "no OTA → clear error" || bad "no OTA: $out"
mkota "$T/desk/Noxis-1.0-20261111-asteroids-ota.zip" 0
out=$(run); grep -q "ohne Signaturzertifikat" <<<"$out" && ok "unsigned OTA refused" || bad "unsigned: $out"
mkota "$T/desk/Noxis-1.0-20261111-asteroids-ota.zip" 1
out=$(run); echo "$out" | grep -q "Veröffentlicht" && ok "publish runs through" || bad "publish: $out"
grep -q "gh release create noxis-20261111 $T/desk/Noxis-1.0-20261111-asteroids-ota.zip" "$T/gh.log" && ok "release tag noxis-20261111 with OTA + .sha256" || bad "gh call: $(cat "$T/gh.log")"
J="$REPO/ota/asteroids.json"
python3 - "$J" "$T/desk/Noxis-1.0-20261111-asteroids-ota.zip" <<'PY' && ok "Updater JSON: datetime from OTA metadata, size, sha256 id, release URL" || bad "json: $(cat "$J")"
import json, sys, hashlib, os
r = json.load(open(sys.argv[1]))["response"][0]
ota = sys.argv[2]
assert r["datetime"] == 1790000000, r
assert r["size"] == os.path.getsize(ota)
assert r["id"] == hashlib.sha256(open(ota, "rb").read()).hexdigest()
assert r["url"] == "https://github.com/Real3rr0r303YT/NoxisOS/releases/download/noxis-20261111/Noxis-1.0-20261111-asteroids-ota.zip", r["url"]
assert r["filename"] == "Noxis-1.0-20261111-asteroids-ota.zip"
PY
git -C "$T/remote.git" log --oneline -1 main 2>/dev/null | grep -q "OTA: Noxis-1.0-20261111" && ok "ota/asteroids.json committed + pushed" || bad "not pushed"
touch "$T/existing"; out=$(run); grep -qE "gh release create noxis-20261111-[0-9]{4} " "$T/gh.log" && ok "same day again → tag gets a time suffix" || bad "dup tag"
mk="$ROOT/vendor/noxis/config/noxis.mk"
grep -q "lineage.updater.uri=https://raw.githubusercontent.com/Real3rr0r303YT/NoxisOS/main/ota/{device}.json" "$mk" && ok "phone Updater reads ota/{device}.json from NoxisOS" || bad "updater uri"
echo; echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
