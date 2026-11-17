#!/usr/bin/env python3
"""Noxis OS – idempotente Patches für den LineageOS-Quellbaum.

Benutzung: noxis_patch.py <android-quellbaum> [--check]
Jeder Patch prüft, ob er schon angewendet ist. Kritische Patches (KernelSU im
Kernel, Noxis-Produkt) brechen ab, wenn ihr Muster nicht gefunden wird.
"""
import os
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
    print(f"[  FEHLER  ] {name}: {why}")


# ------------------------------------------------------------ 1. Noxis-Produkt erben
def p_inherit():
    f = f"{DEV}/lineage_asteroids.mk"
    s = read(f)
    line = "$(call inherit-product, vendor/noxis/config/noxis.mk)"
    if line in s:
        return ok("Noxis-Produkt eingebunden", "schon da")
    anchor = "$(call inherit-product, vendor/lineage/config/common_full_phone.mk)"
    if anchor not in s:
        return fail("Noxis-Produkt eingebunden", f"Anker fehlt in {f}")
    write(f, s.replace(anchor, f"{anchor}\n\n{MARK}\n{line}"))
    ok("Noxis-Produkt eingebunden", "gepatcht")


# ------------------------------------------------------------ 2. KernelSU im Kernel verankern
def p_ksu():
    f = f"{DEV}/BoardConfig.mk"
    s = read(f)
    if re.search(r"^[ \t]*vendor/asteroids_ksu\.config", s, re.M):
        return ok("KernelSU im Kernel (CONFIG_KSU=y)", "schon da")
    new, n = re.subn(r"(\n[ \t]*vendor/asteroids_perf\.config)[ \t]*(?=\n)",
                     r"\1 \\\n    vendor/asteroids_ksu.config", s)
    if n != 1:
        return fail("KernelSU im Kernel (CONFIG_KSU=y)", "TARGET_KERNEL_CONFIG nicht gefunden")
    write(f, new)
    ok("KernelSU im Kernel (CONFIG_KSU=y)", "gepatcht")


def p_ksu_source():
    kconf = "kernel/nothing/sm7635/arch/arm64/configs/vendor/asteroids_ksu.config"
    ksrc = "kernel/nothing/sm7635/KernelSU/kernel/Kbuild"
    if not os.path.exists(path("kernel/nothing/sm7635")):
        return ok("KernelSU-Quellcode im Kernel", "übersprungen (Kernel nicht gesynct)")
    if not os.path.exists(path(ksrc)) or "CONFIG_KSU=y" not in read(kconf):
        return fail("KernelSU-Quellcode im Kernel", f"{ksrc} oder CONFIG_KSU=y fehlt")
    ok("KernelSU-Quellcode im Kernel", "ok")


# ------------------------------------------------------------ 3. Board-Härtung + AVB an
def p_board():
    f = f"{DEV}/BoardConfig.mk"
    s = read(f)
    line = "-include vendor/noxis/config/BoardConfigNoxis.mk"
    if line in s:
        return ok("Noxis-BoardConfig (Kernel-Härtung, Verified Boot)", "schon da")
    write(f, s.rstrip("\n") + f"\n\n{MARK}\n{line}\n")
    ok("Noxis-BoardConfig (Kernel-Härtung, Verified Boot)", "gepatcht")


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
        return ok("Nothing-Kamera optional", "schon da")
    write(fd, d2)
    write(fb, b2)
    ok("Nothing-Kamera optional" + ("" if have else " (nicht vorhanden → entfernt)"), "gepatcht")


# ------------------------------------------------------------ 5. Name im System
def p_version():
    f = "vendor/lineage/config/version.mk"
    s = read(f)
    if "LINEAGE_DISPLAY_VERSION := Noxis-" in s:
        return ok("Versionsname „Noxis“", "schon da")
    new, n = re.subn(r"^LINEAGE_DISPLAY_VERSION := .*$",
                     "LINEAGE_DISPLAY_VERSION := Noxis-$(NOXIS_VERSION)-$(LINEAGE_BUILD_DATE)", s, flags=re.M)
    if n != 1:
        return fail("Versionsname „Noxis“", "LINEAGE_DISPLAY_VERSION nicht gefunden")
    new = new.replace("PRODUCT_VERSION_MAJOR = ", "NOXIS_VERSION ?= 1.0\nPRODUCT_VERSION_MAJOR = ", 1)
    write(f, new)
    ok("Versionsname „Noxis“", "gepatcht")


# ------------------------------------------------------------ 6. Jelly raus, eigener Browser rein
def p_browser():
    # Standardbrowser ist Cromite; Fennec kommt zusaetzlich, wenn F-Droid
    # eine arm64-Fassung hat. Jelly fliegt raus, sobald einer von beiden da
    # ist - frueher hing das allein an Fennec, und faellt der aus, blieb
    # Jelly drin, obwohl Cromite laengst installiert war.
    da = [n for n in ("Cromite", "Fennec")
          if os.path.exists(path(f"vendor/noxis/prebuilt/{n}/{n}.apk"))]
    if not da:
        return ok("Browser Jelly ersetzt", "übersprungen (kein Browser da)")
    f = "vendor/lineage/config/common.mk"
    s = read(f)
    if "    ExactCalculator \\\n    Jelly\n" not in s:
        return ok("Browser Jelly ersetzt", "schon da")
    write(f, s.replace("    ExactCalculator \\\n    Jelly\n", "    ExactCalculator\n"))
    ok("Browser Jelly ersetzt", "gepatcht (" + ", ".join(da) + ")")


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
        return ok("Kamera postproc@1.0-nt", "nicht noetig")
    zeile = f"{PP_SRC}:{PP_DST}"
    l2 = l if PP_DST in l else l.rstrip("\n") + "\n" + f"{MARK}: postproc fuer die Nothing-Kamera\n" + zeile + "\n"
    e2 = e
    if f"'{PP_DST}'" not in e:
        m = re.search(r"\n([ \t]*)\(\n[ \t]*'vendor/lib64/libntofflinepostproc\.so',", e)
        if not m:
            return fail("Kamera postproc@1.0-nt", "Ankerstelle in extract-files.py nicht gefunden")
        ein = m.group(1)
        e2 = (e[:m.start()] + f"\n{ein}'{PP_DST}': blob_fixup()\n{ein}    .fix_soname(),"
              + e[m.start():])
    if l2 == l and e2 == e:
        return ok("Kamera postproc@1.0-nt", "schon da")
    write(fl, l2)
    write(fe, e2)
    ok("Kamera postproc@1.0-nt", "gepatcht")


for p in (p_inherit, p_ksu, p_ksu_source, p_board, p_camera, p_version, p_browser, p_postproc):
    try:
        p()
    except FileNotFoundError as e:
        fail(p.__name__, f"Datei fehlt: {e.filename}")

if any(r[1] == "FEHLER" for r in results):
    sys.exit(1)
