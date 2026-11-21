# Changelog – Noxis OS

Made by 3rr0r303YT on TikTok · GPL-3.0

## 1.5

- **Duress PIN wipes silently:** no "factory reset" dialog and no recovery screen any more – the lock screen shows "wrong PIN", the phone restarts, the recovery wipes with its screen off and powers off. Keystore keys are deleted right away.
- **KernelSU really gone from the kernel:** KernelSU's kernel option is on by default, so removing the device tree's KernelSU fragment in 1.4 was not enough – the 1.4 kernel still contained the KernelSU driver (no manager, no root for apps, but not clean). New fragment `noxis_noroot.config` switches it off; `./noxis.sh build` throws away an old kernel config with KernelSU so the kernel is rebuilt.
- **`./noxis.sh opsec`** now checks the kernel config (`CONFIG_KSU`) and compressed kernels – the 1.4 check could not see inside the kernel image.
- **Verified boot debugging:** `printk.devkmsg=on`, so init's dm-verity/AVB messages are no longer rate-limited away from the boot log.
- **`avb test` / `avb lock` flashed vbmeta with verification OFF:** they used the flash helper that adds `--disable-verity --disable-verification` (fastboot's "Rewriting vbmeta struct") – so the test never tested anything, and `lock` would have locked with verification off (no boot). Now plain `fastboot flash`. `avb status` also recognises dm-verity devices in `/dev/block/mapper`.
- **`./noxis.sh avb`:** `key` before `test` (reversible with `avb unkey`), `status` no longer stops without root, `lock` checks OEM unlocking in the bootloader and flashes vbmeta with verification on first.

- **`./noxis.sh flash`** shows which Noxis version gets installed (and the one on the phone) and asks `y` before wiping.
- **`./noxis.sh sign`** frees space first (older builds in `release/`, aborted sign leftovers in `/tmp`) and checks free space before signing.
- **`avb restore`** clears `slot-unbootable` (`--set-active`).
- **Bootloader lock tested and failed** on the Nothing Phone (3a): red *"Your device is corrupt"* screen, rescued via `fastboot flashing unlock` + `./noxis.sh flash`. `avb lock` is blocked on this phone until the cause is found (README).

## 1.4

- **No root, only OPSEC:** KernelSU removed completely – not in the kernel, no manager, no modules, no `su`. The module NoxisSpoof and `./noxis.sh overlayfix` / `./noxis.sh ksu` are gone. `./noxis.sh apps` deletes old KernelSU leftovers. Requirement for verified boot. **Before updating:** remove all KernelSU modules on the phone.
- **`./noxis.sh avb`**: guarded path to verified boot and a locked bootloader with your own key (test → status → key → lock); refuses to lock while root is on the phone.
- **Google services in the app sandbox:** microG (Services + Companion) as normal user apps via postinstall – LineageOS 24 only accepts microG's official signature for this. `NOXIS_MICROG=0` skips it.
- **Duress PIN (like GrapheneOS):** Noxis Guard → Notfall-PIN. A second PIN that factory-resets the phone when entered on the lock screen. Hash only, never equal to the real PIN, a bug can only disable it – never lock you out.
- **Widgets** in all own apps: clock, battery, calendar, notes, favourites (phone), calculator, camera – Nothing dot-matrix style.

## 1.3

- **NoxisCall is a privileged system app** (like the NothingCall KernelSU module): two-sided call recording works without the module.
- **postinstall:** after a fresh install or factory reset it opens the KernelSU app and waits until you allowed root for Shell, then installs the KernelSU modules (before, they were skipped with a warning).
- **Setup wizard:** the welcome animation shows the Noxis mark instead of the LineageOS logo (it is a Lottie animation, `raw/lottie_welcome`, not the `logo` drawable – `tools/gen_setup_lottie.py`).
- **NoxisCamera** ([NothingCamera](https://github.com/Real3rr0r303YT/NothingCamera)) joins the GrapheneOS Camera: offline, metadata stripped, encrypted vault, zoom up to 40x. The LineageOS camera (Aperture) is removed.

## 1.2

- **Faster, flagship feel:** Settings, launcher and Noxis Guard are compiled fully ahead of time (like SystemUI already was), system_server too – snappier app switching, notifications and launches without JIT warm-up.
- **App installs and the first boot after an update** compile on all 8 cores; background optimisation while charging stays on the small cores for battery.
- **Faster cold starts:** app code is read ahead in one go (Pixel settings).
- **zram 50 % of RAM instead of a fixed 2 GB:** many more apps stay open in the background instead of reloading.
- **Animations 0.75x** by default on fresh installs.
- **publish:** shows upload progress, speed and time left every 15 s; an interrupted upload is completed by running it again (also publishes a left-over draft).
- **publish:** releases are tagged `noxis-<version>-<date>`, older ROM releases are deleted after a successful upload (`NOXIS_KEEP_RELEASES`).
- **OTA fix:** the vbmeta inside the update now has the same verified-boot flags as the first flash – before, an update would not boot and the phone fell back to the old version.
- fastbootd: Noxis logo in red, recovery menus in Noxis blue, fastbootd menus in red.

## 1.1

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
