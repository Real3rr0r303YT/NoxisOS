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


def pfade(zeile):
    """Quell- und Zielpfad aus einer Eintragszeile holen.

    Moegliche Formen:  -pfad   pfad|hash   pfad;MODUL   quelle:ziel
    Das fuehrende '-' heisst 'wird fuer den Bau gebraucht', der Rest sind
    Zusaetze hinter dem Pfad.

    Bei 'quelle:ziel' zaehlen beide: extract-files.py meldet in seiner
    Ausgabe den Zielpfad, eine Weglass-Liste nennt aber oft den, unter dem
    die Datei im Geraet liegt. Mit nur einer Seite rutschen solche Eintraege
    durch.
    """
    s = zeile.strip()
    if not s or s.startswith("#"):
        return ()
    if s.startswith("-"):
        s = s[1:]
    for trenner in ("|", ";"):
        s = s.split(trenner, 1)[0]
    return tuple(t.strip() for t in s.split(":", 1) if t.strip())


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    pfad = sys.argv[1]
    fehlend = {z.strip() for z in sys.stdin if z.strip()}
    if not fehlend:
        print("nothing to remove")
        return 0

    with open(pfad, encoding="utf-8") as f:
        zeilen = f.readlines()

    behalten, weg = [], []
    for z in zeilen:
        treffer = [p for p in pfade(z) if p in fehlend]
        if treffer:
            weg.append(treffer[0])
        else:
            behalten.append(z)

    if not weg:
        print("none of the missing paths is on the list")
        return 0

    with open(pfad, "w", encoding="utf-8") as f:
        f.writelines(behalten)
    for q in weg:
        print("  removed: " + q)
    print("%d entries removed" % len(weg))
    return 0


if __name__ == "__main__":
    sys.exit(main())
