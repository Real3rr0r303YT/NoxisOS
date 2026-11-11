#!/usr/bin/env python3
"""Erzeugt die Argumente für sign_target_files_apks aus einem target_files.zip.

  noxis_sign_args.py <target_files.zip> <keydir> args     → ein Argument pro Zeile
  noxis_sign_args.py <target_files.zip> <keydir> apexes   → APEX-Basisnamen (für Schlüsselerzeugung)

Regeln:
  - APKs mit Standardschlüsseln (testkey/platform/shared/media/…) übernimmt  -d <keydir>
  - PRESIGNED / externe APKs bleiben unverändert
  - alle anderen APKs (z. B. APKs in APEXen) → releasekey
  - jede nicht vorsignierte APEX → eigener Container- und Payload-Schlüssel
  - Verified Boot: vbmeta, boot, recovery, vbmeta_system, vbmeta_vendor → avb.pem (RSA-4096)
"""
import re
import sys
import zipfile

STD = {"testkey", "devkey", "releasekey", "platform", "shared", "media", "networkstack",
       "sdk_sandbox", "bluetooth", "nfc"}
KV = re.compile(r'(\w+)="([^"]*)"')
AVB_PARTS = ["vbmeta", "boot", "recovery", "vbmeta_system", "vbmeta_vendor"]


def parse(text):
    return [dict(KV.findall(line)) for line in text.splitlines() if line.strip()]


def load(tf):
    with zipfile.ZipFile(tf) as z:
        names = set(z.namelist())
        apk = parse(z.read("META/apkcerts.txt").decode()) if "META/apkcerts.txt" in names else []
        apex = parse(z.read("META/apexkeys.txt").decode()) if "META/apexkeys.txt" in names else []
    return apk, apex


def std_cert(cert):
    m = re.match(r"^build/(make/)?target/product/security/([\w.-]+)\.x509\.pem$", cert)
    return bool(m) and m.group(2) in STD


def apex_base(name):
    return name[:-6] if name.endswith(".capex") else name[:-5] if name.endswith(".apex") else name


def signable_apexes(apex):
    return [a for a in apex if a.get("name") and a.get("private_key") not in ("PRESIGNED", "")]


def build_args(tf, kd):
    apk, apex = load(tf)
    args = ["-o", "-d", kd]
    apex_names = {a["name"] for a in apex}
    for a in apk:
        name, cert = a.get("name", ""), a.get("certificate", "")
        if not name or name in apex_names or cert in ("PRESIGNED", "") or std_cert(cert):
            continue
        args += ["--extra_apks", f"{name}={kd}/releasekey"]
    for a in signable_apexes(apex):
        base = apex_base(a["name"])
        args += ["--extra_apks", f"{a['name']}={kd}/{base}",
                 "--extra_apex_payload_key", f"{a['name']}={kd}/{base}.pem"]
    for p in AVB_PARTS:
        args += [f"--avb_{p}_key", f"{kd}/avb.pem", f"--avb_{p}_algorithm", "SHA256_RSA4096"]
    return args


def main():
    if len(sys.argv) != 4 or sys.argv[3] not in ("args", "apexes"):
        sys.exit(__doc__)
    tf, kd, mode = sys.argv[1:]
    if mode == "apexes":
        _, apex = load(tf)
        print("\n".join(sorted({apex_base(a["name"]) for a in signable_apexes(apex)})))
    else:
        print("\n".join(build_args(tf, kd)))


if __name__ == "__main__":
    main()
