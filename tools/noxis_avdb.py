#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Noxis OS – Copyright (C) 2026 3rr0r (Real3rr0r303YT) – Made by 3rr0r303YT on TikTok
#
# Virus signatures for Noxis Guard. Downloads ClamAV's official databases
# (main.cvd + daily.cvd), keeps only the hash signatures of Android malware
# ("Andr.*" in .hdb = MD5 and .hsb = SHA-1/SHA-256). Output, all sorted so
# Noxis Guard can binary-search them straight from storage without loading
# hundreds of thousands of hashes into RAM:
#   android_md5.idx / android_sha1.idx / android_sha256.idx
#       fixed records: raw hash bytes + 4-byte big-endian index into names
#   android.names   one malware name per line
#   VERSION         date and ClamAV database versions
# Offline: the phone itself never talks to ClamAV.
#
#   noxis_avdb.py <out-dir> [cache-dir]
#
# A .cvd is a 512-byte text header ("ClamAV-VDB:date:version:...") followed by
# a gzip-compressed tar. ClamAV's CDN rate-limits, so the files are cached
# and fetched again at most once a day.
import io
import struct
import os
import sys
import tarfile
import time
import urllib.request

MIRROR = "https://database.clamav.net"
UA = "ClamAV/1.4.3 (OS: linux, ARCH: x86_64, CPU: x86_64) noxis-os"
PREFIXES = ("Andr.",)


def fetch(name, cache):
    path = os.path.join(cache, name)
    if os.path.exists(path) and time.time() - os.path.getmtime(path) < 86400:
        return path
    req = urllib.request.Request(f"{MIRROR}/{name}", headers={"User-Agent": UA})
    tmp = path + ".part"
    try:
        with urllib.request.urlopen(req, timeout=900) as r, open(tmp, "wb") as f:
            while True:
                b = r.read(1 << 20)
                if not b:
                    break
                f.write(b)
        os.replace(tmp, path)
    except Exception as e:
        if os.path.exists(tmp):
            os.remove(tmp)
        if os.path.exists(path):
            print(f"[warn] {name}: download failed ({e}) – using the cached copy", file=sys.stderr)
            return path
        raise
    return path


def read_cvd(path):
    with open(path, "rb") as f:
        head = f.read(512).decode("ascii", "replace")
        if not head.startswith("ClamAV-VDB:"):
            raise ValueError(f"{path}: not a ClamAV database")
        parts = head.split(":")
        data = f.read()
    tar = tarfile.open(fileobj=io.BytesIO(data), mode="r:gz")
    return parts[1].strip(), parts[2].strip(), tar


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: noxis_avdb.py <out-dir> [cache-dir]")
    out = sys.argv[1]
    cache = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.cache/noxis/clamav")
    os.makedirs(out, exist_ok=True)
    os.makedirs(cache, exist_ok=True)
    sigs, ver = {}, []          # raw hash bytes -> name
    for db in ("main.cvd", "daily.cvd"):
        date, version, tar = read_cvd(fetch(db, cache))
        ver.append(f"{db.split('.')[0]} {version}")
        for m in tar.getmembers():
            ext = m.name.rsplit(".", 1)[-1]
            if ext not in ("hdb", "hsb") or not m.isfile():
                continue
            for raw in tar.extractfile(m).read().decode("utf-8", "replace").splitlines():
                p = raw.split(":")
                if len(p) < 3 or not p[2].startswith(PREFIXES):
                    continue
                try:
                    h = bytes.fromhex(p[0].strip())
                except ValueError:
                    continue
                if len(h) in (16, 20, 32):
                    sigs[h] = p[2].strip()
    if not sigs:
        sys.exit("no Android signatures found – ClamAV format changed?")
    names = sorted(set(sigs.values()))
    nid = {n: i for i, n in enumerate(names)}
    count = {}
    for size, label in ((16, "md5"), (20, "sha1"), (32, "sha256")):
        recs = sorted(h for h in sigs if len(h) == size)
        count[label] = len(recs)
        with open(os.path.join(out, f"android_{label}.idx"), "wb") as f:
            for h in recs:
                f.write(h + struct.pack(">I", nid[sigs[h]]))
    with open(os.path.join(out, "android.names"), "w") as f:
        f.write("\n".join(names) + "\n")
    with open(os.path.join(out, "VERSION"), "w") as f:
        f.write(f"Stand {time.strftime('%d.%m.%Y')} (ClamAV {', '.join(ver)})\n")
    print(f"{len(sigs)} Android signatures (" + ", ".join(f"{v} {k}" for k, v in count.items()) + ")")


if __name__ == "__main__":
    main()
