# ============================================================
#  Noxis OS – Produktkonfiguration
#  Wird von device/nothing/asteroids/lineage_asteroids.mk geerbt
# ============================================================
NOXIS_VERSION := 1.0
NOXIS_PATH := vendor/noxis

# Identität
PRODUCT_SYSTEM_EXT_PROPERTIES += \
    ro.noxis.version=$(NOXIS_VERSION) \
    ro.noxis.device=asteroids

# Eigene OTA-Updates statt LineageOS-Server (JSON auf GitHub)
PRODUCT_SYSTEM_EXT_PROPERTIES += \
    lineage.updater.uri=https://raw.githubusercontent.com/Real3rr0r303YT/noxis-ota/main/{device}.json

# ---------------- Apps ----------------
PRODUCT_PACKAGES += \
    NoxisGuard \
    privapp-permissions-noxis.xml \
    NoxisFrameworksOverlay \
    NoxisSystemUIOverlay

# Vorgebaute, signierte Apps (von noxis.sh geladen)
ifneq ($(wildcard $(NOXIS_PATH)/prebuilt/GrapheneCamera/GrapheneCamera.apk),)
PRODUCT_PACKAGES += GrapheneCamera
endif
ifneq ($(wildcard $(NOXIS_PATH)/prebuilt/GraphenePdfViewer/GraphenePdfViewer.apk),)
PRODUCT_PACKAGES += GraphenePdfViewer
endif
ifneq ($(wildcard $(NOXIS_PATH)/prebuilt/Fennec/Fennec.apk),)
PRODUCT_PACKAGES += Fennec
endif
ifneq ($(wildcard $(NOXIS_PATH)/prebuilt/MullvadVPN/MullvadVPN.apk),)
PRODUCT_PACKAGES += MullvadVPN
endif
ifneq ($(wildcard $(NOXIS_PATH)/prebuilt/TorBrowser/TorBrowser.apk),)
PRODUCT_PACKAGES += TorBrowser
endif
# KernelSU-Manager: Root-Freigabe pro App (Kernel-Treiber steckt in kernel/nothing/sm7635/KernelSU)
ifneq ($(wildcard $(NOXIS_PATH)/prebuilt/KernelSU/KernelSU.apk),)
PRODUCT_PACKAGES += KernelSU
endif

# eSIM ohne Google
NOXIS_ESIM ?= true
ifeq ($(NOXIS_ESIM),true)
ifneq ($(wildcard packages/apps/OpenEUICC/Android.bp),)
PRODUCT_PACKAGES += OpenEUICC
endif
endif

