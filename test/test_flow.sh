#!/usr/bin/env bash
# Ablauftest für noxis.sh: externe Tools sind Attrappen, Gerätebaum + LineageOS-Dateien echt.
#   test/test_flow.sh <crdroid-device-tree> <lineage-vendor-config-dir> <sample-target_files.zip>
set -uo pipefail
NOXIS="$(cd "$(dirname "$0")/.." && pwd)"
DEVTREE="$1"; LCONF="$2"; TFZIP="$3"
W=$(mktemp -d); BIN="$W/bin"; LOG="$W/calls.log"; mkdir -p "$BIN"
export NOXIS_SRC="$W/src" NOXIS_KEYS="$W/keys" NOXIS_OUT="$W/release" HOME="$W/home"
mkdir -p "$HOME"
pass=0; fail=0
ok()  { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }

cat > "$BIN/repo" <<EOF
#!/bin/sh
echo "repo \$*" >> $LOG
case "\$1" in
  init) mkdir -p .repo ;;
  sync)
    mkdir -p device/nothing vendor/lineage development/tools external/avb build
    cp -r "$DEVTREE" device/nothing/asteroids
    printf '#!/bin/sh\nmkdir -p ../../../vendor/nothing/asteroids && touch ../../../vendor/nothing/asteroids/asteroids-vendor.mk && echo "extract \$1" >> $LOG\n' > device/nothing/asteroids/extract-files.py
    chmod +x device/nothing/asteroids/extract-files.py
    cp -r "$LCONF" vendor/lineage/config
    printf '#!/bin/sh\nread pw\nopenssl genrsa 2048 2>/dev/null | openssl pkcs8 -topk8 -outform DER -nocrypt -out "\$1.pk8"\necho cert > "\$1.x509.pem"\n' > development/tools/make_key
    chmod +x development/tools/make_key
    printf 'import sys\nopen(sys.argv[sys.argv.index("--output")+1],"wb").write(b"PKMD")\n' > external/avb/avbtool.py
    cat > build/envsetup.sh <<'ENV'
breakfast() { echo "breakfast \$*" >> LOGF; export ANDROID_PRODUCT_OUT="\$PWD/out/target/product/asteroids"; }
mka() { echo "mka \$*" >> LOGF; d="\$ANDROID_PRODUCT_OUT/obj/PACKAGING/target_files_intermediates"; mkdir -p "\$d"; cp TFZ "\$d/lineage_asteroids-target_files.zip"; }
sign_target_files_apks() { echo "sign \$*" >> LOGF; n=\$#; cp "\${@: -2:1}" "\${@: -1}"; }
ota_from_target_files() { echo "ota \$*" >> LOGF; echo OTA > "\${@: -1}"; }
img_from_target_files() { echo "img \$*" >> LOGF; t=\$(mktemp -d); for p in boot vendor_boot dtbo vbmeta vbmeta_system vbmeta_vendor; do echo x > \$t/\$p.img; done; (cd \$t && zip -q "\${@: -1}" *.img); }
ENV
    sed -i "s|LOGF|$LOG|g; s|TFZ|$TFZIP|g" build/envsetup.sh ;;
esac
EOF
cat > "$BIN/curl" <<EOF
#!/bin/sh
echo "curl \$*" >> $LOG
case "\$*" in
  *"%{url_effective}"*releases/latest*) echo "https://github.com/x/y/releases/tag/71" ;;
  *GrapheneOS/Camera/releases/expanded_assets*)    echo '<a href="/GrapheneOS/Camera/releases/download/71/Camera-71.apk">' ; echo '<a href="/GrapheneOS/Camera/releases/download/71/Camera-71.apk.idsig">' ;;
  *GrapheneOS/PdfViewer/releases/expanded_assets*) echo '<a href="/GrapheneOS/PdfViewer/releases/download/71/PdfViewer-33.apk">' ;;
  *f-droid.org/api/v1/packages/org.mozilla.fennec_fdroid*) echo '{"packageName":"org.mozilla.fennec_fdroid","suggestedVersionCode":1590120,"packages":[{"versionName":"159.0.1","versionCode":1590120},{"versionName":"159.0.1","versionCode":1590110},{"versionName":"159.0.1","versionCode":1590100},{"versionName":"159.0.0","versionCode":1590020}]}' ;;
  *fennec_fdroid_1590110.apk*) out=\$(echo "\$*" | sed 's/.*-o \([^ ]*\).*/\1/'); t=\$(mktemp -d); mkdir -p \$t/lib/arm64-v8a; echo so > \$t/lib/arm64-v8a/libxul.so; (cd \$t && zip -qr "\$out" lib) ;;
  *fennec_fdroid_*.apk*)       out=\$(echo "\$*" | sed 's/.*-o \([^ ]*\).*/\1/'); t=\$(mktemp -d); mkdir -p \$t/lib/armeabi-v7a; echo so > \$t/lib/armeabi-v7a/libxul.so; (cd \$t && zip -qr "\$out" lib) ;;
  *tiann/KernelSU/releases/expanded_assets/v3.3.1*) echo '<a href="/tiann/KernelSU/releases/download/v3.3.1/KernelSU_v3.3.1_32703-release.apk">'; echo '<a href="/tiann/KernelSU/releases/download/v3.3.1/ksud-aarch64-linux-android">' ;;
  *dist.torproject.org/torbrowser/) echo '<a href="16.0a14/">a</a> <a href="16.0/">b</a> <a href="15.0.9/">c</a> <a href="noscript/">n</a>' ;;
  *-o*) out=\$(echo "\$*" | sed 's/.*-o \([^ ]*\).*/\1/'); echo APK > "\$out" ;;
esac
EOF
cat > "$BIN/fastboot" <<EOF
#!/bin/sh
echo "fastboot \$*" >> $LOG
[ "\$1 \$2" = "getvar product" ] && echo "product: Asteroids" >&2
exit 0
EOF
printf '#!/bin/sh\necho "adb $*" >> %s\n' "$LOG" > "$BIN/adb"
printf '#!/bin/sh\nexit 0\n' > "$BIN/git-lfs"
chmod +x "$BIN"/*
export PATH="$BIN:$PATH"
cd "$NOXIS"
find "$NOXIS/vendor/noxis/prebuilt" -delete 2>/dev/null

./noxis.sh check >/dev/null 2>&1;                        ok "check läuft" "true"
./noxis.sh sync > "$W/sync.out" 2>&1;                    ok "sync" "grep -q 'Noxis-Produkt eingebunden' $W/sync.out && grep -q 'repo init -u https://github.com/LineageOS/android.git -b lineage-24.0' $LOG"
ok "local manifest kopiert" "[ -f $NOXIS_SRC/.repo/local_manifests/noxis.xml ]"
ok "vendor/noxis im Baum" "[ -f $NOXIS_SRC/vendor/noxis/packages/NoxisGuard/Android.bp ]"
ok "KernelSU im Kernel-Config" "grep -q '^    vendor/asteroids_ksu.config' $NOXIS_SRC/device/nothing/asteroids/BoardConfig.mk"
ok "dm-verity bleibt an (Standard)" "grep -q 'BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS :=\$' $NOXIS_SRC/vendor/noxis/config/BoardConfigNoxis.mk"
ok "sync: --depth=1 (init + sync)" "grep -q 'repo init .*--depth=1' $LOG && grep -q 'repo sync .*--depth=1' $LOG"
./noxis.sh apps > "$W/apps.out" 2>&1;                    ok "apps" "[ -f vendor/noxis/prebuilt/GrapheneCamera/GrapheneCamera.apk ] && [ -f vendor/noxis/prebuilt/Fennec/Fennec.apk ]"
ok "apps: richtige Assets (kein .idsig)" "grep -q 'Camera-71.apk\$' $W/apps.out"
ok "apps: Fennec arm64 gewählt (nicht armv7)" "grep -q 'Fennec ← F-Droid 159.0.1 (1590110, arm64-v8a)' $W/apps.out && unzip -l vendor/noxis/prebuilt/Fennec/Fennec.apk | grep -q arm64-v8a"
ok "apps: Cromite entfernt" "! grep -rqi cromite noxis.sh vendor/noxis/config/noxis.mk"
ok "apps: Android.bp erzeugt" "grep -q 'name: \"GraphenePdfViewer\"' vendor/noxis/prebuilt/GraphenePdfViewer/Android.bp"
ok "apps: Mullvad + Tor (aarch64, neueste stabile)" "[ -f vendor/noxis/prebuilt/MullvadVPN/MullvadVPN.apk ] && grep -q 'torbrowser/16.0/tor-browser-android-aarch64-16.0.apk' $W/apps.out"
ok "apps: KernelSU-Manager v3.3.1 (passend zum Kernel)" "[ -f vendor/noxis/prebuilt/KernelSU/KernelSU.apk ] && grep -q 'KernelSU_v3.3.1_32703-release.apk' $W/apps.out"
ok "apps: alle Apps im Produkt" "grep -q 'PRODUCT_PACKAGES += KernelSU' vendor/noxis/config/noxis.mk && grep -q 'PRODUCT_PACKAGES += TorBrowser' vendor/noxis/config/noxis.mk"
ok "apps: Jelly durch Firefox ersetzt" "! grep -q '    Jelly' $NOXIS_SRC/vendor/lineage/config/common.mk"
./noxis.sh build > "$W/b0.out" 2>&1;                     ok "build ohne Blobs bricht ab" "grep -q 'Erst ./noxis.sh blobs' $W/b0.out"
echo zip > "$W/ota.zip"
./noxis.sh blobs "$W/ota.zip" > "$W/blobs.out" 2>&1;     ok "blobs" "grep -q 'B4.1-260928-1204' $W/blobs.out && grep -q 'extract $W/ota.zip' $LOG"
./noxis.sh keys > "$W/keys.out" 2>&1;                    ok "keys" "[ -f $NOXIS_KEYS/releasekey.pk8 ] && [ -f $NOXIS_KEYS/avb.pem ]"
ok "keys: avb.pem ist RSA-4096" "openssl rsa -in $NOXIS_KEYS/avb.pem -noout -text 2>/dev/null | grep -q '4096 bit'"
ok "keys: Rechte 600" "[ \"\$(stat -c %a $NOXIS_KEYS/avb.pem)\" = 600 ]"
./noxis.sh build > "$W/build.out" 2>&1;                  ok "build: user-Variante" "grep -q 'breakfast asteroids user' $LOG && grep -q 'mka target-files-package otatools' $LOG"
./noxis.sh sign > "$W/sign.out" 2>&1;                    ok "sign" "ls $NOXIS_OUT/Noxis-1.0-*-asteroids-ota.zip >/dev/null 2>&1"
ok "sign: AVB mit eigenem Schlüssel" "grep -q -- '--avb_vbmeta_key $NOXIS_KEYS/avb.pem' $LOG"
ok "sign: APEX-Schlüssel erzeugt" "[ -f $NOXIS_KEYS/com.android.adbd.pem ] && [ -f $NOXIS_KEYS/com.android.art.pem ]"
ok "sign: OTA-JSON gültig" "python3 -c 'import json,sys; json.load(open(\"$NOXIS_OUT/asteroids.json\"))'"
ok "sign: Prüfsummen" "ls $NOXIS_OUT/*.sha256 >/dev/null"
ok "cleanup: ROM auf dem Desktop" "ls $HOME/Desktop/Noxis-1.0-*-asteroids-ota.zip $HOME/Desktop/Noxis-1.0-*-asteroids-img.zip >/dev/null 2>&1"
ok "cleanup: out/ gelöscht" "[ ! -d $NOXIS_SRC/out ]"
ok "cleanup: Quellcode unangetastet" "[ -f $NOXIS_SRC/build/envsetup.sh ] && [ -d $NOXIS_SRC/device/nothing/asteroids ]"
ok "cleanup: target_files weg, OTA bleibt" "! ls $NOXIS_OUT/*-target_files.zip >/dev/null 2>&1 && ls $NOXIS_OUT/*-ota.zip >/dev/null"
./noxis.sh cleanup > "$W/c2.out" 2>&1
ok "cleanup: zweiter Lauf ohne out/ ok" "grep -q 'out/ nicht vorhanden' $W/c2.out"
printf 'ja\n\n' | ./noxis.sh flash > "$W/flash.out" 2>&1
ok "flash: Reihenfolge boot→vendor_boot→dtbo→vbmeta" "grep -o 'fastboot flash [a-z_]*' $LOG | awk '{print \$3}' | paste -sd, | grep -q '^boot,vendor_boot,dtbo,vbmeta,vbmeta_system,vbmeta_vendor\$'"
ok "flash: sideload OTA" "grep -q 'adb sideload .*-ota.zip' $LOG"
ok "flash: Bootloader wird nie gesperrt" "! grep -q 'flashing lock\|avb_custom_key' $LOG"
ok "flash: Hinweis Root pro App" "grep -q 'Superuser → App antippen' $W/flash.out"

find "$NOXIS/vendor/noxis/prebuilt" -delete 2>/dev/null
echo; echo "$pass bestanden, $fail fehlgeschlagen"; echo "Logs: $W"
[ "$fail" -eq 0 ]
