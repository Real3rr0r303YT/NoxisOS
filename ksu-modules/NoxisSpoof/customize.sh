# SPDX-License-Identifier: GPL-3.0-or-later
# Noxis OS – Copyright (C) 2026 3rr0r (Real3rr0r303YT) – Made by 3rr0r303YT on TikTok
MODDIR=$MODPATH
. "$MODPATH/common.sh"
show
ui_print "- Noxis Device Spoof"
ui_print "- Apps will see: $NAME ($MODEL) after the reboot"
ui_print "- Other profiles: KernelSU app → Modules → Action button"
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
