#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Noxis OS – Copyright (C) 2026 3rr0r (Real3rr0r303YT)
# Made by 3rr0r303YT on TikTok
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. It comes WITHOUT ANY WARRANTY.
"""Prueft VOR dem Bauen, ob jede privilegierte Berechtigung unserer priv-apps
in der Allowlist steht. Fehlt eine, stuerzt system_server beim ersten Start
ab (Bootschleife) - das soll nach 10 Minuten auffallen, nicht nach 10 Stunden.

Welche Berechtigungen privilegiert sind, steht im Quellbaum:
frameworks/base/core/res/AndroidManifest.xml (protectionLevel mit "privileged").

Aufruf: noxis_privapp_check.py <quellbaum> <vendor/noxis>
"""
import glob
import os
import re
import sys
import xml.etree.ElementTree as ET

A = "{http://schemas.android.com/apk/res/android}"


def privilegierte(src):
    mf = os.path.join(src, "frameworks/base/core/res/AndroidManifest.xml")
    if not os.path.exists(mf):
        sys.exit(f"[privapp] {mf} is missing – run ./noxis.sh sync first")
    out = set()
    for p in ET.parse(mf).getroot().iter("permission"):
        lvl = p.get(A + "protectionLevel", "")
        if "privileged" in lvl.split("|"):
            out.add(p.get(A + "name"))
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, vendor = sys.argv[1:]
    priv = privilegierte(src)
    erlaubt = {}
    for xf in glob.glob(os.path.join(vendor, "permissions", "*.xml")):
        for pa in ET.parse(xf).getroot().iter("privapp-permissions"):
            erlaubt.setdefault(pa.get("package"), set()).update(
                p.get("name") for p in pa.iter("permission"))
    fehler = 0
    for bp in glob.glob(os.path.join(vendor, "packages", "*", "Android.bp")):
        if not re.search(r"privileged:\s*true", open(bp).read()):
            continue
        d = os.path.dirname(bp)
        root = ET.parse(os.path.join(d, "AndroidManifest.xml")).getroot()
        pkg = root.get("package")
        brauchen = {u.get(A + "name") for u in root.iter("uses-permission")} & priv
        fehlt = sorted(brauchen - erlaubt.get(pkg, set()))
        if fehlt:
            fehler += 1
            print(f"[privapp] {pkg}: missing in vendor/noxis/permissions/*.xml:")
            for f in fehlt:
                print(f'          <permission name="{f}" />')
        else:
            print(f"[privapp] {pkg}: {len(brauchen)} privileged permissions, all allowed")
    sys.exit(1 if fehler else 0)


if __name__ == "__main__":
    main()
