# SPDX-License-Identifier: GPL-3.0-or-later
# Noxis OS – Copyright (C) 2026 3rr0r (Real3rr0r303YT) – Made by 3rr0r303YT on TikTok
# Shared by post-fs-data.sh and action.sh. The chosen profile survives module
# updates because it lives outside the module folder.
CONF=/data/adb/noxis-spoof.conf
PROFILE=1
[ -f "$CONF" ] && . "$CONF"
COUNT=$(grep -c '|' "$MODDIR/profiles.txt")
case "$PROFILE" in ''|*[!0-9]*) PROFILE=1 ;; esac
[ "$PROFILE" -ge 1 ] && [ "$PROFILE" -le "$COUNT" ] || PROFILE=1
LINE=$(sed -n "${PROFILE}p" "$MODDIR/profiles.txt")
NAME=${LINE%%|*};  REST=${LINE#*|}
BRAND=${REST%%|*}; REST=${REST#*|}
MANUF=${REST%%|*}; MODEL=${REST#*|}

show() {  # current profile in the module list of the KernelSU app
  local what="Apps see: $NAME ($MODEL)."
  [ -z "$BRAND" ] && what="Spoofing off – apps see the real Nothing Phone (3a)."
  sed -i "s/^description=.*/description=$what Action button = next profile, then reboot. Made by 3rr0r303YT on TikTok (GPL-3.0)/" "$MODDIR/module.prop"
}
