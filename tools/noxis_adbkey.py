#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Noxis OS – Copyright (C) 2026 3rr0r (Real3rr0r303YT)
# Made by 3rr0r303YT on TikTok
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. It comes WITHOUT ANY WARRANTY.
"""Debug-Hilfe: den ADB-Schluessel des eigenen PCs in init_boot und recovery
einbauen, damit "adb logcat" schon waehrend des ersten Starts geht (in einem
user-Build ist ADB sonst nicht freigegeben, und ohne fertig gestartetes
Android gibt es keinen Dialog zum Erlauben).

Nichts wird neu kompiliert: das Image wird ausgepackt, an die Ramdisk wird ein
zweites cpio-Archiv mit /adb_keys angehaengt (der Kernel liest aneinander-
gehaengte Archive nacheinander ein), dann wird es wieder eingepackt.

Aufruf: noxis_adbkey.py <img.zip> <adbkey.pub> <mkbootimg-ordner> <ausgabe-ordner>
"""
import gzip
import os
import struct
import subprocess
import sys
import tempfile
import zipfile

LZ4_LEGACY = b"\x02\x21\x4c\x18"


def cpio_newc(files):
    """Ein newc-cpio-Archiv aus [(name, daten), ...] plus TRAILER."""
    out = b""
    ino = 0x4e58  # beliebig, nur eindeutig im Archiv
    for n, d, m in [(n, d, 0o100644) for n, d in files] + [("TRAILER!!!", b"", 0)]:
        nb = n.encode() + b"\0"
        hdr = "070701" + "".join(f"{v:08X}" for v in (
            ino, m, 0, 0, 1, 0, len(d), 0, 0, 0, 0, len(nb), 0))
        ino += 1
        rec = hdr.encode() + nb
        rec += b"\0" * (-len(rec) % 4)
        rec += d + b"\0" * (-len(d) % 4)
        out += rec
    return out + b"\0" * (-len(out) % 512)


# Android-eigener Weg, einen user-Build bei OFFENEM Bootloader debugbar zu
# starten (first_stage_init: /force_debuggable -> /debug_ramdisk/adb_debug.prop
# wird mit hoechster Prioritaet geladen). Bei gesperrtem Bootloader ignoriert
# init das. Hier nur: ADB beim Start an, Schluessel bleibt Pflicht.
ADB_DEBUG_PROP = b"""# Noxis OS debugadb - nur zur Fehlersuche
persist.sys.usb.config=adb
"""


def lz4_legacy_literal(data):
    """LZ4-Legacy-Rahmen mit einem Block, der nur aus Literalen besteht –
    gueltiges LZ4 ohne Kompressor; die Datei ist ohnehin winzig."""
    n = len(data)
    if n < 15:
        blk = bytes([n << 4])
    else:
        rest = n - 15
        blk = bytes([0xF0]) + b"\xff" * (rest // 255) + bytes([rest % 255])
    blk += data
    return LZ4_LEGACY + struct.pack("<I", len(blk)) + blk


def patch(img, files, mkb, out):
    with tempfile.TemporaryDirectory() as t:
        arg = subprocess.run(
            [sys.executable, os.path.join(mkb, "unpack_bootimg.py"), "--boot_img", img,
             "--out", t, "--format=mkbootimg", "-0"],
            check=True, capture_output=True).stdout.split(b"\0")
        # jedes Argument endet mit \0 - nur das letzte, leere Stueck weg;
        # leere Werte wie --cmdline "" muessen bleiben
        if arg and arg[-1] == b"":
            arg.pop()
        arg = [a.decode() for a in arg]
        if "--ramdisk" not in arg:
            raise SystemExit(f"{img}: keine Ramdisk gefunden")
        rd = arg[arg.index("--ramdisk") + 1]
        orig = open(rd, "rb").read()
        extra = cpio_newc(files)
        if orig[:4] == LZ4_LEGACY:
            extra = lz4_legacy_literal(extra)
        elif orig[:2] == b"\x1f\x8b":
            extra = gzip.compress(extra)
        elif orig[:6] != b"070701":
            raise SystemExit(f"{img}: unbekannte Ramdisk-Kompression {orig[:4].hex()}")
        with open(rd, "wb") as f:
            f.write(orig + extra)
        subprocess.run([sys.executable, os.path.join(mkb, "mkbootimg.py"), *arg,
                        "--output", out], check=True)


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    zipf, keyf, mkb, outdir = sys.argv[1:]
    key = open(keyf, "rb").read()
    if not key.strip():
        sys.exit(f"{keyf} ist leer")
    os.makedirs(outdir, exist_ok=True)
    with tempfile.TemporaryDirectory() as t, zipfile.ZipFile(zipf) as z:
        for name in ("init_boot", "recovery"):
            if f"{name}.img" not in z.namelist():
                print(f"  {name}.img nicht im Paket – uebersprungen")
                continue
            src = z.extract(f"{name}.img", t)
            dst = os.path.join(outdir, f"{name}-adb.img")
            files = [("adb_keys", key)]
            if name == "init_boot":
                files += [("force_debuggable", b""), ("adb_debug.prop", ADB_DEBUG_PROP)]
            patch(src, files, mkb, dst)
            print(f"  {dst}")


if __name__ == "__main__":
    main()
