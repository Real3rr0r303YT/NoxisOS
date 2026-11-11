# ============================================================
#  Noxis OS – Board-Konfiguration (am Ende von BoardConfig.mk eingebunden)
#  Modell: offener Bootloader + KernelSU (Root nur pro freigegebener App)
# ============================================================

# Kernel-Härtung (GrapheneOS-ähnlich)
BOARD_KERNEL_CMDLINE += \
    init_on_alloc=1 \
    init_on_free=1 \
    page_alloc.shuffle=1 \
    slab_nomerge \
    randomize_kstack_offset=on

# dm-verity bleibt an: System-, Vendor- und Produkt-Partition werden beim Lesen geprüft.
# KernelSU-Module arbeiten per Overlay und brauchen kein abgeschaltetes Verity.
# Notfall-Schalter, falls es auf dem Gerät Probleme gibt:  NOXIS_DISABLE_VERITY=true
ifeq ($(NOXIS_DISABLE_VERITY),true)
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS := --flags 3
else
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS :=
endif

# Eigene Bootanimation
TARGET_BOOTANIMATION := vendor/noxis/bootanimation/bootanimation.zip
TARGET_SCREEN_WIDTH := 1080
TARGET_SCREEN_HEIGHT := 2392
