#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Noxis OS – Copyright (C) 2026 3rr0r (Real3rr0r303YT) – Made by 3rr0r303YT on TikTok
# Only the values apps read through android.os.Build (brand, manufacturer,
# model) of the system-side partitions are changed. vendor/odm stay real -
# the camera, modem and sensor drivers check those and would break otherwise.
MODDIR=$(dirname "$0")
. "$MODDIR/common.sh"
RP=$(command -v resetprop || echo /data/adb/ksu/bin/resetprop)
for ns in "" system. product. system_ext.; do
  "$RP" -n "ro.product.${ns}brand" "$BRAND"
  "$RP" -n "ro.product.${ns}manufacturer" "$MANUF"
  "$RP" -n "ro.product.${ns}model" "$MODEL"
done
show
