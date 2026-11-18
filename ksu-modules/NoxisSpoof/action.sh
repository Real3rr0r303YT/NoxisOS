#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Noxis OS – Copyright (C) 2026 3rr0r (Real3rr0r303YT) – Made by 3rr0r303YT on TikTok
# Action button in the KernelSU app: switch to the next profile.
MODDIR=$(dirname "$0")
. "$MODDIR/common.sh"
PROFILE=$(( PROFILE % COUNT + 1 ))
echo "PROFILE=$PROFILE" > "$CONF"
. "$MODDIR/common.sh"
show
echo "Next profile: $NAME ($MODEL)"
echo "Reboot to apply."
