#!/usr/bin/env python3
"""Noxis OS – idempotente Patches für den LineageOS-Quellbaum.

Benutzung: noxis_patch.py <android-quellbaum> [--check]
Jeder Patch prüft, ob er schon angewendet ist. Kritische Patches (KernelSU im
Kernel, Noxis-Produkt) brechen ab, wenn ihr Muster nicht gefunden wird.
"""
import os
import shutil
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
CHECK = "--check" in sys.argv
MARK = "# noxis-patch"
DEV = "device/nothing/asteroids"
results = []


def path(p):
    return os.path.join(ROOT, p)


def read(p):
    with open(path(p), encoding="utf-8") as f:
        return f.read()


def write(p, s):
    if CHECK:
        return
    with open(path(p), "w", encoding="utf-8") as f:
        f.write(s)


def ok(name, state):
    results.append((name, state))
    print(f"[{state:^10}] {name}")


def fail(name, why):
    results.append((name, "FEHLER"))
    print(f"[  ERROR   ] {name}: {why}")


# ------------------------------------------------------------ 1. Noxis-Produkt erben
def p_inherit():
    f = f"{DEV}/lineage_asteroids.mk"
    s = read(f)
    line = "$(call inherit-product, vendor/noxis/config/noxis.mk)"
    if line in s:
        return ok("Noxis product included", "already done")
    anchor = "$(call inherit-product, vendor/lineage/config/common_full_phone.mk)"
    if anchor not in s:
        return fail("Noxis product included", f"anchor missing in {f}")
    write(f, s.replace(anchor, f"{anchor}\n\n{MARK}\n{line}"))
    ok("Noxis product included", "patched")


# ------------------------------------------------------------ 2. KernelSU im Kernel verankern
KSU_OFF = "vendor/noxis_noroot.config"

def p_ksu():
    """Noxis has no root. KernelSU's Kconfig says "default y" - dropping the
    device tree's KernelSU fragment is NOT enough, the driver stays in the
    kernel. Our own last fragment switches it off explicitly."""
    frag = "kernel/nothing/sm7635/arch/arm64/configs/" + KSU_OFF
    want = "# Noxis OS: no root - Made by 3rr0r303YT on TikTok (GPL-3.0)\n# CONFIG_KSU is not set\n"
    if not os.path.isdir(os.path.join(ROOT, os.path.dirname(frag))):
        return fail("KernelSU off in the kernel (no root)", "kernel tree missing: " + os.path.dirname(frag))
    if not os.path.exists(os.path.join(ROOT, frag)) or read(frag) != want:
        write(frag, want)
    f = f"{DEV}/BoardConfig.mk"
    s = read(f)
    new = re.sub(r"[ \t]*\\\n[ \t]*vendor/asteroids_ksu\.config[ \t]*(?=\n)", "", s)
    if KSU_OFF not in new:
        new, n = re.subn(r"(TARGET_KERNEL_CONFIG := \\\n(?:[ \t]+\S+[ \t]*\\\n)*[ \t]+\S+)",
                         lambda m: m.group(1) + " \\\n    " + KSU_OFF, new, count=1)
        if not n:
            return fail("KernelSU off in the kernel (no root)", "TARGET_KERNEL_CONFIG not found")
    if "asteroids_ksu.config" in new:
        return fail("KernelSU off in the kernel (no root)", "asteroids_ksu.config in an unexpected place")
    if new != s:
        write(f, new)
        return ok("KernelSU off in the kernel (no root)", "patched")
    ok("KernelSU off in the kernel (no root)", "already done")


# ------------------------------------------------------------ 3. Board-Härtung + AVB an
def p_board():
    f = f"{DEV}/BoardConfig.mk"
    s = read(f)
    line = "-include vendor/noxis/config/BoardConfigNoxis.mk"
    if line in s:
        return ok("Noxis BoardConfig (kernel hardening, verified boot)", "already done")
    write(f, s.rstrip("\n") + f"\n\n{MARK}\n{line}\n")
    ok("Noxis BoardConfig (kernel hardening, verified boot)", "patched")


# ------------------------------------------------------------ 4. Nothing-Kamera optional
def p_camera():
    have = os.path.exists(path("vendor/nothing/camera/config/Asteroids.mk"))
    fd, fb = f"{DEV}/device.mk", f"{DEV}/BoardConfig.mk"
    d, b = read(fd), read(fb)
    d2 = d.replace("$(call inherit-product, vendor/nothing/camera/config/Asteroids.mk)",
                   "$(call inherit-product-if-exists, vendor/nothing/camera/config/Asteroids.mk)")
    b2 = b.replace("\ninclude vendor/nothing/camera/asteroids/BoardConfigCamera.mk",
                   "\n-include vendor/nothing/camera/asteroids/BoardConfigCamera.mk")
    if not have:
        d2 = re.sub(r"# Glyph lights for Nothing Camera\nPRODUCT_PACKAGES \+= \\\n[ \t]*libglyph_lights_shim\n",
                    f"{MARK}: Nothing-Kamera nicht vorhanden\n", d2)
    if d2 == d and b2 == b:
        return ok("Nothing camera optional", "already done")
    write(fd, d2)
    write(fb, b2)
    ok("Nothing camera optional" + ("" if have else " (not present → removed)"), "patched")


# ------------------------------------------------------------ 5. Name im System
def p_version():
    # LINEAGE_DISPLAY_VERSION: name of the build in Settings/OTA.
    # LINEAGE_VERSION: ro.lineage.version - shown in Settings → About phone →
    # "NoxisOS version" (otherwise "24.0-DATE-UNOFFICIAL-asteroids").
    f = "vendor/lineage/config/version.mk"
    s = read(f)
    m = re.search(r"^NOXIS_VERSION := (\S+)", read("vendor/noxis/config/noxis.mk"), re.M)
    ver = m.group(1) if m else "1.0"
    if ("LINEAGE_DISPLAY_VERSION := Noxis-" in s and "LINEAGE_VERSION := Noxis-" in s
            and f"NOXIS_VERSION ?= {ver}\n" in s):
        return ok(f"Version name \"Noxis {ver}\"", "already done")
    new = s
    if "LINEAGE_DISPLAY_VERSION := Noxis-" not in new:
        new, n = re.subn(r"^LINEAGE_DISPLAY_VERSION := .*$",
                         "LINEAGE_DISPLAY_VERSION := Noxis-$(NOXIS_VERSION)-$(LINEAGE_BUILD_DATE)", new, flags=re.M)
        if n < 1:
            return fail("Version name \"Noxis\"", "LINEAGE_DISPLAY_VERSION not found")
    if "LINEAGE_VERSION := Noxis-" not in new:
        new, n = re.subn(r"^(\s*)LINEAGE_VERSION := .*$",
                         r"\1LINEAGE_VERSION := Noxis-$(NOXIS_VERSION)-$(LINEAGE_BUILD_DATE)-$(LINEAGE_BUILD)", new, flags=re.M)
        if n < 1:
            return fail("Version name \"Noxis\"", "LINEAGE_VERSION not found")
    # version.mk may be read before noxis.mk, so it carries the same number
    if re.search(r"^NOXIS_VERSION \?= ", new, re.M):
        new = re.sub(r"^NOXIS_VERSION \?= .*$", f"NOXIS_VERSION ?= {ver}", new, flags=re.M)
    else:
        new = new.replace("PRODUCT_VERSION_MAJOR = ", f"NOXIS_VERSION ?= {ver}\nPRODUCT_VERSION_MAJOR = ", 1)
    write(f, new)
    ok(f"Version name \"Noxis {ver}\"", "patched")


# ------------------------------------------------------------ 6. Jelly raus, eigener Browser rein
def p_browser():
    # Default browser is IronFox (Firefox + uBlock Origin). Jelly only goes
    # when it was really downloaded - never a phone without a browser.
    da = [n for n in ("IronFox",)
          if os.path.exists(path(f"vendor/noxis/prebuilt/{n}/{n}.apk"))]
    if not da:
        return ok("Browser Jelly replaced", "skipped (no browser present)")
    f = "vendor/lineage/config/common.mk"
    s = read(f)
    if "    ExactCalculator \\\n    Jelly\n" not in s:
        return ok("Browser Jelly replaced", "already done")
    write(f, s.replace("    ExactCalculator \\\n    Jelly\n", "    ExactCalculator\n"))
    ok("Browser Jelly replaced", "patched (" + ", ".join(da) + ")")


# ------------------------------------------------------------ 7. Kamera: postproc@1.0-nt bereitstellen
# extract-files.py biegt libntofflinepostproc und den postproc-Dienst per
# replace_needed auf "vendor.qti.camera.postproc@1.0-nt.so" um - damit die
# Herstellerfassung nicht mit der gleichnamigen, aus dem Quellcode gebauten
# HIDL-Bibliothek kollidiert. Bereitgestellt wird das Modul im oeffentlichen
# crDroid-Baum aber nirgends; der Bau bricht ab mit
#   "libntofflinepostproc" depends on undefined module "vendor.qti.camera.postproc@1.0-nt"
# Also: die Herstellerdatei unter dem neuen Namen mitnehmen und ihren SONAME
# anpassen. Ohne den neuen SONAME haelt der Linker zur Laufzeit beide
# Fassungen fuer dieselbe Bibliothek, und die Kamera stuerzt ab.
PP_SRC = "vendor/lib64/vendor.qti.hardware.camera.postproc@1.0.so"
PP_DST = "vendor/lib64/vendor.qti.camera.postproc@1.0-nt.so"


def p_postproc():
    fl, fe = f"{DEV}/proprietary-files.txt", f"{DEV}/extract-files.py"
    l, e = read(fl), read(fe)
    if "vendor.qti.camera.postproc@1.0-nt" not in e:
        return ok("Camera postproc@1.0-nt", "not needed")
    zeile = f"{PP_SRC}:{PP_DST}"
    l2 = l if PP_DST in l else l.rstrip("\n") + "\n" + f"{MARK}: postproc fuer die Nothing-Kamera\n" + zeile + "\n"
    e2 = e
    if f"'{PP_DST}'" not in e:
        m = re.search(r"\n([ \t]*)\(\n[ \t]*'vendor/lib64/libntofflinepostproc\.so',", e)
        if not m:
            return fail("Camera postproc@1.0-nt", "anchor in extract-files.py not found")
        ein = m.group(1)
        e2 = (e[:m.start()] + f"\n{ein}'{PP_DST}': blob_fixup()\n{ein}    .fix_soname(),"
              + e[m.start():])
    if l2 == l and e2 == e:
        return ok("Camera postproc@1.0-nt", "already done")
    write(fl, l2)
    write(fe, e2)
    ok("Camera postproc@1.0-nt", "patched")


# ------------------------------------------------------------ 9. Fehlende Shims
# Der Geraetebaum haengt einigen Blobs per add_needed() Shim-Bibliotheken an.
# Manche davon (z.B. libntcam_session_shim) kommen aus dem nicht oeffentlichen
# Repo vendor/nothing/camera. Fehlt eine, bricht der Bau mit "depends on
# undefined module" ab. Dann fliegt nur dieses add_needed() raus: der Blob
# laeuft wie in Nothing OS, nur ohne die Zusatzfunktion der Nothing-Kamera.
SHIM_SUCHE = ("device", "hardware", "vendor/nothing/camera", "vendor/noxis", "vendor/lineage")


def shim_definiert(name):
    muster = re.compile(r'name:\s*"' + re.escape(name) + r'"')
    for wurzel in SHIM_SUCHE:
        for d, dirs, files in os.walk(path(wurzel)):
            dirs[:] = [x for x in dirs if not x.startswith(".")]
            if "Android.bp" in files:
                try:
                    if muster.search(open(os.path.join(d, "Android.bp"), errors="ignore").read()):
                        return True
                except OSError:
                    pass
    return False


def p_shims():
    fe = f"{DEV}/extract-files.py"
    e = read(fe)
    weg = [n for n in sorted(set(re.findall(r"\.add_needed\('([A-Za-z0-9_]+_shim)\.so'\)", e)))
           if not shim_definiert(n)]
    if not weg:
        return ok("Shims", "all present")
    e2 = e
    for n in weg:
        # Eintrag, der nur aus diesem add_needed besteht: ganz raus
        e2 = re.sub(r"\n[ \t]*'[^']+': blob_fixup\(\)\n[ \t]*\.add_needed\('" + re.escape(n) + r"\.so'\),",
                    "", e2)
        # sonst nur die eine Zeile
        e2 = re.sub(r"\n[ \t]*\.add_needed\('" + re.escape(n) + r"\.so'\)", "", e2)
    write(fe, e2)
    ok("Shims (missing → removed: " + ", ".join(weg) + ")", "patched")



# ------------------------------------------------------------ 10. OpenEUICC-Manifeste
# OpenEUICC (master) setzt den Paketnamen nur noch per "namespace" in Gradle,
# nicht mehr im AndroidManifest.xml. Soong liest Gradle nicht und bricht ab:
# "manifest:package attribute is not declared". Wir tragen den namespace aus
# der build.gradle(.kts) des jeweiligen Moduls als package= ins Manifest ein.
EUICC = "packages/apps/OpenEUICC"


def p_openeuicc():
    wurzel = path(EUICC)
    if not os.path.isdir(wurzel):
        return ok("OpenEUICC manifests", "not present")
    geaendert, fehlt = [], []
    for d, dirs, files in os.walk(wurzel):
        dirs[:] = [x for x in dirs if not x.startswith(".") and x not in ("build", "test", "androidTest")]
        if "AndroidManifest.xml" not in files:
            continue
        mf = os.path.join(d, "AndroidManifest.xml")
        text = open(mf, encoding="utf-8").read()
        m = re.search(r"<manifest\b[^>]*>", text, re.S)
        if not m or re.search(r"\bpackage\s*=", m.group(0)):
            continue
        # Modulordner: der Ordner ueber src/<variante>/
        modul = d
        teile = os.path.relpath(d, wurzel).split(os.sep)
        if "src" in teile:
            modul = os.path.join(wurzel, *teile[:teile.index("src")])
        ns = None
        for g in ("build.gradle.kts", "build.gradle"):
            gp = os.path.join(modul, g)
            if os.path.exists(gp):
                n = re.search(r"""namespace\s*=?\s*["']([\w.]+)["']""", open(gp, encoding="utf-8").read())
                if n:
                    ns = n.group(1)
                    break
        rel = os.path.relpath(mf, path(""))
        if not ns:
            fehlt.append(rel)
            continue
        neu_tag = m.group(0).replace("<manifest", f'<manifest package="{ns}"', 1)
        if not CHECK:
            with open(mf, "w", encoding="utf-8") as fh:
                fh.write(text[:m.start()] + neu_tag + text[m.end():])
        geaendert.append(f"{rel} → {ns}")
    for g in geaendert:
        print(f"             {g}")
    if fehlt:
        return fail("OpenEUICC manifests", "no namespace found for: " + ", ".join(fehlt))
    ok("OpenEUICC manifests", "patched" if geaendert else "already done")


# ------------------------------------------------------------ Recovery: Noxis logo + version
def p_recovery():
    """LineageOS recovery + fastbootd: Noxis logos (vendor/noxis/branding/recovery),
    Noxis menu colours and "NoxisOS 1.1 (DATE)" instead of "Version 24.0 (DATE)"."""
    name = "Recovery/fastbootd branding (logo, colours, NoxisOS version)"
    rec = "bootable/recovery"
    if not os.path.isdir(path(rec)):
        return ok(name, "skipped (no bootable/recovery)")
    changed = False
    src_dir = path("vendor/noxis/branding/recovery")
    for root, _, files in os.walk(src_dir):
        for fn in files:
            rel = os.path.relpath(os.path.join(root, fn), src_dir)
            dst = path(os.path.join(rec, rel))
            if not os.path.isdir(os.path.dirname(dst)):
                continue
            new = open(os.path.join(root, fn), "rb").read()
            if not os.path.exists(dst) or open(dst, "rb").read() != new:
                if not CHECK:
                    with open(dst, "wb") as fh:
                        fh.write(new)
                changed = True
    f = f"{rec}/recovery.cpp"
    s = read(f)
    old = '"Version " + android::base::GetProperty("ro.lineage.build.version", "(unknown)") +'
    new = ('"NoxisOS " + (android::base::StartsWith(ver, "Noxis-") ? '
           'ver.substr(6, ver.find(\'-\', 6) - 6) : '
           'android::base::GetProperty("ro.lineage.build.version", "(unknown)")) +')
    if old in s:
        write(f, s.replace(old, new, 1))
        changed = True
    elif new not in s:
        return fail(name, "title line in recovery.cpp not found")
    # menu colours: recovery purple/pink -> Noxis blue, fastbootd orange/yellow -> red
    f = f"{rec}/recovery_ui/screen_ui.cpp"
    s = read(f)
    a, b = s.find("void ScreenRecoveryUI::SetColor("), s.find("case UIElement::LOG:")
    note = ""
    if a < 0 or b < a:
        note = " (menu colours: SetColor not found, kept)"
    else:
        body = s[a:b]
        for o, n in (("0xf8, 0x90, 0xff", "0x7f, 0xa8, 0xff"),
                     ("0x7c * 0.20, 0x4d * 0.20, 0xff * 0.20", "0x7f * 0.20, 0xa8 * 0.20, 0xff * 0.20"),
                     ("0x7c, 0x4d, 0xff", "0x3d, 0x5a, 0xa8"),
                     ("0xfd, 0xd8, 0x35", "0xff, 0x78, 0x78"),
                     ("0xfd, 0xd8,0x35", "0xff, 0x78, 0x78"),
                     ("0xe6 * 0.20, 0x51 * 0.20, 0x00 * 0.20", "0xd7 * 0.20, 0x19 * 0.20, 0x21 * 0.20"),
                     ("0xe6, 0x51, 0x00", "0xd7, 0x19, 0x21"),
                     ("if (fastbootd_logo_enabled_)\n        gr_color(0, 0, 0, 255);",
                      "if (fastbootd_logo_enabled_)\n        gr_color(0xf0, 0xf4, 0xfa, 255);")):
            body = body.replace(o, n)
        if body != s[a:b]:
            write(f, s[:a] + body + s[b:])
            changed = True
    ok(name, ("patched" if changed else "already done") + note)


# ------------------------------------------------------------ Easter egg: Noxis instead of LineageOS
def p_easteregg():
    """Settings → About phone → tap the NoxisOS version: LineageParts' egg
    (colourful LineageOS logo) becomes the Noxis dot-matrix egg."""
    name = "Easter egg (Noxis instead of LineageOS)"
    dst = "packages/apps/LineageParts/src/org/lineageos/lineageparts/logo/PlatLogoActivity.java"
    if not os.path.exists(path(dst)):
        return ok(name, "skipped (LineageParts not found)")
    new = read("vendor/noxis/patches/LineageParts/PlatLogoActivity.java")
    if read(dst) == new:
        return ok(name, "already done")
    write(dst, new)
    ok(name, "patched")


# ------------------------------------------------------------ zram: 50 % of RAM instead of fixed 2 GB
def p_zram():
    """The device tree swaps to a fixed 2 GB zram. Flagships (Pixel) use half
    the RAM: more apps stay in memory instead of being killed and reloaded.
    zram writeback to flash (512M) stays as it is."""
    name = "zram 50 % of RAM (instead of 2 GB)"
    f = "device/nothing/asteroids/init/fstab.zram.2g"
    if not os.path.exists(path(f)):
        return ok(name, "skipped (fstab.zram.2g not found)")
    s = read(f)
    if "zramsize=50%" in s:
        return ok(name, "already done")
    import re
    n, k = re.subn(r"zramsize=\d+", "zramsize=50%", s, count=1)
    if not k:
        return fail(name, "zramsize= not found in " + f)
    write(f, n)
    ok(name, "patched")


# ------------------------------------------------------------ Duress PIN (like GrapheneOS)
def p_duress():
    """Second PIN that wipes the phone (set in Noxis Guard). NoxisDuress.java is copied next
    to LockSettingsService, which gets two calls: check before verifying a credential, and
    cleanup when the lock credential changes. Anchors missing -> FAIL, never a half patch."""
    name = "Duress PIN (LockSettingsService)"
    d = "frameworks/base/services/core/java/com/android/server/locksettings"
    f = f"{d}/LockSettingsService.java"
    if not os.path.exists(path(f)):
        return ok(name, "skipped (frameworks/base not synced)")
    src = path("vendor/noxis/patches/frameworks_base/NoxisDuress.java")
    dst = path(f"{d}/NoxisDuress.java")
    copied = not os.path.exists(dst) or open(src).read() != open(dst).read()
    if copied:
        shutil.copyfile(src, dst)
    s = read(f)
    hook1_anchor = 'Slogf.i(TAG, "Verifying lockscreen credential for user %d", userId);\n'
    hook1 = ("        // Noxis: duress PIN (Noxis Guard) wipes the phone instead of unlocking\n"
             "        if (userId == UserHandle.USER_SYSTEM && NoxisDuress.matches(mStorage, credential)) {\n"
             "            NoxisDuress.wipe(mContext);\n"
             "            return VerifyCredentialResponse.fromError();\n"
             "        }\n")
    hook2_anchor = "            credential.validateBasicRequirements();\n"
    hook2 = "            NoxisDuress.onCredentialChanged(mStorage, credential, userId);\n"
    changed = False
    if "NoxisDuress.matches(" not in s:
        if s.count(hook1_anchor) != 1:
            return fail(name, "verify anchor not found exactly once")
        s = s.replace(hook1_anchor, hook1_anchor + hook1, 1)
        changed = True
    if "NoxisDuress.onCredentialChanged(" not in s:
        i = s.find("public boolean setLockCredential(")
        j = s.find(hook2_anchor, i) if i >= 0 else -1
        if j < 0:
            return fail(name, "setLockCredential anchor not found")
        s = s[:j + len(hook2_anchor)] + hook2 + s[j + len(hook2_anchor):]
        changed = True
    if changed:
        write(f, s)
    ok(name, "patched" if (changed or copied) else "already done")


def p_duress_recovery():
    """Duress wipe without a visible "factory reset": with --reason=noxis_duress the recovery
    uses the stub UI (draws nothing, like quiescent mode), wipes /data and powers off."""
    name = "Duress PIN: silent wipe in the recovery"
    f = "bootable/recovery/recovery_main.cpp"
    if not os.path.exists(path(f)):
        return ok(name, "skipped (no bootable/recovery)")
    s = read(f)
    old = 'if (android::base::GetBoolProperty("ro.boot.quiescent", false)) {'
    new = ('if (android::base::GetBoolProperty("ro.boot.quiescent", false) ||\n'
           '      reason.rfind("noxis_duress", 0) == 0) {  // Noxis: duress PIN wipes silently')
    if new in s:
        return ok(name, "already done")
    if s.count(old) != 1:
        return fail(name, "quiescent check in recovery_main.cpp not found exactly once")
    if s.find("std::string reason;") < 0 or s.find("std::string reason;") > s.find(old):
        return fail(name, "reason is not parsed before the UI is set up")
    write(f, s.replace(old, new, 1))
    ok(name, "patched")


for p in (p_inherit, p_ksu, p_board, p_camera, p_version, p_browser, p_postproc, p_shims, p_openeuicc,
          p_recovery, p_easteregg, p_zram, p_duress, p_duress_recovery):
    try:
        p()
    except FileNotFoundError as e:
        fail(p.__name__, f"file missing: {e.filename}")

if any(r[1] == "FEHLER" for r in results):
    sys.exit(1)
