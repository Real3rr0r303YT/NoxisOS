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
z.writestr("META-INF/com/android/metadata", "ota-type=AB\npost-timestamp=1790000000\npre-device=asteroids\npost-sdk-level=37\npost-security-patch-level=2026-11-01\nota-property-files=payload_metadata.bin:100:200,payload.bin:100:1024,payload_properties.txt:2000:150\n")
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
[ "\$1 \$2" = "release download" ] && [ -f "$T/remote_sha" ] && { cat "$T/remote_sha"; exit 0; }
[ "\$1 \$2" = "release view" ] && [ -f "$T/existing" ] && exit 0
[ "\$1 \$2" = "release view" ] && exit 1
[ "\$1 \$2" = "release list" ] && [ -f "$T/list" ] && { cat "$T/list"; exit 0; }
exit 0
SH
chmod 755 "$T/bin/gh"
run() {
  PATH="$T/bin:$PATH" bash -c "set -euo pipefail
c(){ echo \"[c] \$*\"; }; warn(){ echo \"[warn] \$*\"; }; die(){ echo \"[die] \$*\"; exit 1; }; need(){ command -v \"\$1\" >/dev/null || die \"\$1 fehlt\"; }
desktop_dir(){ echo '$T/desk'; }
NOXIS='$REPO'; REL='$T/out'; DEVICE=asteroids
$block
cmd_publish" 2>&1
}
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t

out=$(run); grep -q "No signed OTA" <<<"$out" && ok "no OTA → clear error" || bad "no OTA: $out"
mkota "$T/desk/Noxis-1.0-20261111-asteroids-ota.zip" 0
out=$(run); grep -q "without signing certificate" <<<"$out" && ok "unsigned OTA refused" || bad "unsigned: $out"
mkota "$T/desk/Noxis-1.0-20261111-asteroids-ota.zip" 1
out=$(run); echo "$out" | grep -q "Published" && ok "publish runs through" || bad "publish: $out"
grep -q "gh release create noxis-1.0-20261111 $T/desk/Noxis-1.0-20261111-asteroids-ota.zip" "$T/gh.log" && ok "release tag noxis-1.0-20261111 with OTA + .sha256" || bad "gh call: $(cat "$T/gh.log")"
J="$REPO/ota/asteroids.json"
python3 - "$J" "$T/desk/Noxis-1.0-20261111-asteroids-ota.zip" <<'PY' && ok "Updater JSON (lineage-24 v2): array, datetime/sdk/patch from OTA metadata, files[0] sha256/size/url" || bad "json: $(cat "$J")"
import json, sys, hashlib, os
data = json.load(open(sys.argv[1]))
assert isinstance(data, list) and len(data) == 1, data
r = data[0]
ota = sys.argv[2]
assert r["datetime"] == 1790000000, r
assert r["type"] == "unofficial" and r["version"] == "24.0", r
f = r["files"][0]
assert f["size"] == os.path.getsize(ota)
assert f["sha256"] == hashlib.sha256(open(ota, "rb").read()).hexdigest()
assert f["url"] == "https://github.com/Real3rr0r303YT/NoxisOS/releases/download/noxis-1.0-20261111/Noxis-1.0-20261111-asteroids-ota.zip", f["url"]
assert f["filename"] == "Noxis-1.0-20261111-asteroids-ota.zip"
assert f["os_sdk_level"] == 37 and f["os_patch_level"] == "2026-11-01", f
assert f["ota_property_files"].startswith("payload_metadata.bin:"), f
PY
git -C "$T/remote.git" log --oneline -1 main 2>/dev/null | grep -q "OTA: Noxis-1.0-20261111" && ok "ota/asteroids.json committed + pushed" || bad "not pushed"
touch "$T/existing"; out=$(run); grep -qE "gh release create noxis-1.0-20261111-[0-9]{4} " "$T/gh.log" && ok "same day again → tag gets a time suffix" || bad "dup tag"
python3 - "$T/desk/Noxis-1.0-20261112-asteroids-img.zip" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1], "w")
for n in ("boot", "init_boot", "vendor_boot", "recovery", "dtbo", "vbmeta", "system"):
    z.writestr(n + ".img", n.encode() * 100)
z.close()
PY
mkota "$T/desk/Noxis-1.0-20261112-asteroids-ota.zip" 1; touch -d '+1 min' "$T/desk/Noxis-1.0-20261112-asteroids-ota.zip"
: > "$T/gh.log"; rm -f "$T/existing"; out=$(run)
line=$(grep "release create noxis-1.0-20261112 " "$T/gh.log")
ok_all=1; for f in boot.img init_boot.img vendor_boot.img recovery.img dtbo.img vbmeta.img Noxis-1.0-20261112-asteroids-img.zip SHA256SUMS; do grep -q "/$f" <<<"$line" || ok_all=0; done
[ $ok_all = 1 ] && ok "release has boot/init_boot/vendor_boot/recovery/dtbo/vbmeta + img.zip + SHA256SUMS" || bad "images missing: $line / $out"
grep -q "system.img" <<<"$line" && bad "system.img uploaded alone" || ok "big images only inside img.zip"
grep -q -- "--notes" <<<"$line" && grep -q "noxis.sh flash" "$T/gh.log" && ok "release notes with install steps" || bad "notes: $line"
touch "$T/existing"; cp "$T/desk/Noxis-1.0-20261112-asteroids-ota.zip.sha256" "$T/remote_sha"; : > "$T/gh.log"; out=$(run)
grep -q "release upload noxis-1.0-20261112 " "$T/gh.log" && ! grep -q "release create" "$T/gh.log" && ok "same OTA again → completes the existing release, no second one" || bad "resume: $(cat "$T/gh.log") $out"
rm -f "$T/remote_sha" "$T/existing"
mk="$ROOT/vendor/noxis/config/noxis.mk"
grep -q "lineage.updater.uri=https://raw.githubusercontent.com/Real3rr0r303YT/NoxisOS/main/ota/{device}.json" "$mk" && ok "phone Updater reads ota/{device}.json from NoxisOS" || bad "updater uri"
# Old ROM releases are deleted after a successful publish, noxis-apps stays
rm -f "$T/existing" "$T/remote_sha"; printf 'noxis-1.0-20261113\nnoxis-apps\nnoxis-20261111\nnoxis-1.0-20261110\n' > "$T/list"
mkota "$T/desk/Noxis-1.0-20261113-asteroids-ota.zip" 1; touch -d '+2 min' "$T/desk/Noxis-1.0-20261113-asteroids-ota.zip"; : > "$T/gh.log"; out=$(run)
grep -q "release delete noxis-20261111 " "$T/gh.log" && grep -q "release delete noxis-1.0-20261110 " "$T/gh.log" \
  && ! grep -q "release delete noxis-apps" "$T/gh.log" && ! grep -q "release delete noxis-1.0-20261113" "$T/gh.log" \
  && ok "old releases deleted, apps release and new release kept" || bad "prune: $(grep delete "$T/gh.log") $out"
: > "$T/gh.log"; out=$(NOXIS_KEEP_RELEASES=2 run)
grep -c "release delete" "$T/gh.log" | grep -qx 1 && grep -q "release delete noxis-1.0-20261110 " "$T/gh.log" && ok "NOXIS_KEEP_RELEASES=2 keeps the newest old one" || bad "keep=2: $(grep delete "$T/gh.log")"
: > "$T/gh.log"; out=$(NOXIS_KEEP_RELEASES=0 run)
! grep -q "release delete" "$T/gh.log" && ok "NOXIS_KEEP_RELEASES=0 keeps all" || bad "keep=0"
echo; echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
