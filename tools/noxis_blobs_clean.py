#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Noxis OS – Made by 3rr0r303YT on TikTok
# https://github.com/Real3rr0r303YT/NoxisOS
"""Eintraege aus proprietary-files.txt entfernen, deren Datei im Abzug fehlt.

Die fehlenden Pfade kommen ueber die Standardeingabe, einer je Zeile - genau
so, wie extract-files.py sie als "<pfad>: file not found" meldet. Damit
haengt das Aufraeumen an dem, was das Extraktionsskript selbst feststellt,
und nicht an einer Annahme darueber, wie der Abzug aufgebaut ist.

    noxis_blobs_clean.py <proprietary-files.txt>  < liste-der-fehlenden
"""
import sys


def quelle(zeile):
    """Den Quellpfad aus einer Eintragszeile holen.

    Moegliche Formen:  -pfad   pfad|hash   pfad;MODUL   quelle:ziel
    Das fuehrende '-' heisst 'wird fuer den Bau gebraucht', der Rest sind
    Zusaetze hinter dem Pfad.
    """
    s = zeile.strip()
    if not s or s.startswith("#"):
        return None
    if s.startswith("-"):
        s = s[1:]
    for trenner in ("|", ";"):
        s = s.split(trenner, 1)[0]
    return s.split(":", 1)[0].strip()


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    pfad = sys.argv[1]
    fehlend = {z.strip() for z in sys.stdin if z.strip()}
    if not fehlend:
        print("nichts zu entfernen")
        return 0

    with open(pfad, encoding="utf-8") as f:
        zeilen = f.readlines()

    behalten, weg = [], []
    for z in zeilen:
        q = quelle(z)
        if q and q in fehlend:
            weg.append(q)
        else:
            behalten.append(z)

    if not weg:
        print("keiner der fehlenden Pfade steht in der Liste")
        return 0

    with open(pfad, "w", encoding="utf-8") as f:
        f.writelines(behalten)
    for q in weg:
        print("  entfernt: " + q)
    print("%d Eintraege entfernt" % len(weg))
    return 0


if __name__ == "__main__":
    sys.exit(main())
