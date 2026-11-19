# Changelog – Noxis OS

Made by 3rr0r303YT on TikTok · GPL-3.0

## 1.1

- **fastbootd in Noxis look:** Noxis logo in red with "FASTBOOTD" instead of the orange LineageOS one; recovery menus in Noxis blue, fastbootd menus in red (were purple/orange).
- **No LineageOS branding left where you look:** Noxis logo, name and colours on the System updates card, Noxis logo in the setup wizard (the overlay now replaces the right resource), Noxis logo and "NoxisOS 1.1 (DATE)" in the recovery instead of the LineageOS logo and "Version 24.0".
- **New easter egg:** Settings → About phone → tap the NoxisOS version a few times – a Nothing-style dot matrix draws the Noxis mark, every touch sends a wave through the dots, seven taps show a message, a long press shows the credit.
- **Updates from GitHub work:** the System updates app of LineageOS 24 reads a new JSON format; `./noxis.sh publish` writes it, and the release now also carries `boot.img`, `init_boot.img`, `vendor_boot.img`, `recovery.img`, `dtbo.img`, `vbmeta*.img`, the split image zip and `SHA256SUMS`.
- **Noxis Guard virus scan:** ClamAV Android signatures (offline) + trojan patterns, new apps are checked at install.
- **Restart with the cable plugged in** boots Android instead of the black charging screen.
- **Apps:** IronFox (Firefox + uBlock Origin) as default browser, F-Droid, Aurora Store, Termux; Cromite, Fennec and the Noxis launcher removed.
- **KernelSU:** official v3.3.1 in the kernel and the matching manager; module **NoxisSpoof** (switchable device model, *Off* = real device).
- **Build script:** `out/` is kept after signing (fast rebuilds), time left shown during the build (`./noxis.sh eta`), `./noxis.sh overlayfix` for overlay fixes without a build, version number from `vendor/noxis/config/noxis.mk`.

**Updating from 1.0:** Settings → System → System updates. After the update, remove the module *Noxis overlay hotfix* in the KernelSU app (its overlay is now part of the system).

## 1.0

First release: LineageOS 24.0 / Android 17 for the Nothing Phone (3a), own signing keys, KernelSU, Noxis Guard, own apps in Nothing design.
