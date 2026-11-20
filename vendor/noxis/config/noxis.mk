# ============================================================
#  Noxis OS – Produktkonfiguration
#  Wird von device/nothing/asteroids/lineage_asteroids.mk geerbt
# ============================================================
NOXIS_VERSION := 1.4
NOXIS_PATH := vendor/noxis
# Root: 1 = KernelSU in the kernel + manager + modules; 0 = no root at all
# (needed for verified boot / a locked bootloader). Read by noxis.sh and
# tools/noxis_patch.py too.
NOXIS_ROOT := 0

# Identität
PRODUCT_SYSTEM_EXT_PROPERTIES += \
    ro.noxis.version=$(NOXIS_VERSION) \
    ro.noxis.device=asteroids \
    ro.noxis.root=$(NOXIS_ROOT)

# Own OTA updates instead of LineageOS servers: Settings → System → Updater reads this JSON,
# downloads the OTA from the GitHub release and checks it against your release key
# (OS + Nothing firmware: modem, bootloader, DSPs are part of every OTA)
PRODUCT_SYSTEM_EXT_PROPERTIES += \
    lineage.updater.uri=https://raw.githubusercontent.com/Real3rr0r303YT/NoxisOS/main/ota/{device}.json

# ---------------- Apps ----------------
PRODUCT_PACKAGES += \
    NoxisGuard \
    privapp-permissions-noxis.xml \
    privapp-permissions-noxis-product.xml \
    default-permissions-noxis.xml \
    NoxisFrameworksOverlay \
    NoxisSystemUIOverlay \
    NoxisSetupWizardOverlay \
    NoxisLineageSdkOverlay \
    NoxisUpdaterOverlay \
    NoxisSettingsProviderOverlay

# Vorgebaute, signierte Apps (von noxis.sh geladen)
ifneq ($(wildcard $(NOXIS_PATH)/prebuilt/GrapheneCamera/GrapheneCamera.apk),)
PRODUCT_PACKAGES += GrapheneCamera
endif
ifneq ($(wildcard $(NOXIS_PATH)/prebuilt/GraphenePdfViewer/GraphenePdfViewer.apk),)
PRODUCT_PACKAGES += GraphenePdfViewer
endif
ifneq ($(wildcard $(NOXIS_PATH)/prebuilt/IronFox/IronFox.apk),)
PRODUCT_PACKAGES += IronFox
endif
ifneq ($(wildcard $(NOXIS_PATH)/prebuilt/FDroid/FDroid.apk),)
PRODUCT_PACKAGES += FDroid
endif
ifneq ($(wildcard $(NOXIS_PATH)/prebuilt/AuroraStore/AuroraStore.apk),)
PRODUCT_PACKAGES += AuroraStore
endif
ifneq ($(wildcard $(NOXIS_PATH)/prebuilt/MullvadVPN/MullvadVPN.apk),)
PRODUCT_PACKAGES += MullvadVPN
endif
ifneq ($(wildcard $(NOXIS_PATH)/prebuilt/TorBrowser/TorBrowser.apk),)
PRODUCT_PACKAGES += TorBrowser
endif
# Virus signatures for Noxis Guard (ClamAV, Android malware, /product/etc/noxis/av)
ifneq ($(wildcard $(NOXIS_PATH)/prebuilt/NoxisAvDb/android.names),)
PRODUCT_PACKAGES += noxis_av_android_md5.idx noxis_av_android_sha1.idx noxis_av_android_sha256.idx \
    noxis_av_android.names noxis_av_VERSION
endif
# KernelSU-Manager: Root-Freigabe pro App (Kernel-Treiber steckt in kernel/nothing/sm7635/KernelSU)
ifneq ($(wildcard $(NOXIS_PATH)/prebuilt/KernelSU/KernelSU.apk),)
PRODUCT_PACKAGES += KernelSU
endif

# 3rr0r's own apps (Nothing design, built from source by the "Noxis apps" GitHub Action)
# They replace LineageOS' calendar, clock and calculator; phone/notes/battery are added.
NOXIS_OWN_APPS := NoxisCalendar NoxisClock NoxisCalculator NoxisNotes NoxisCall NoxisBattery NoxisCamera
PRODUCT_PACKAGES += $(foreach a,$(NOXIS_OWN_APPS),$(if $(wildcard $(NOXIS_PATH)/prebuilt/$(a)/$(a).apk),$(a)))

# eSIM ohne Google
NOXIS_ESIM ?= true
ifeq ($(NOXIS_ESIM),true)
ifneq ($(wildcard packages/apps/OpenEUICC/Android.bp),)
PRODUCT_PACKAGES += OpenEUICC
endif
endif


# ------------------------------------------------------------ Debug-Build
# NOXIS_DEBUG=1 ./noxis.sh build: ADB laeuft ab dem ersten Start ohne
# Freigabe-Dialog (der braucht ein fertig gestartetes Android). Nur zur
# Fehlersuche bei Bootschleifen - die OPSEC-Pruefung warnt davor.
# noxis.sh legt die Datei an (Umgebungsvariablen erreichen Kati nicht sicher)
-include vendor/noxis/config/noxis_debug.mk
ifeq ($(NOXIS_DEBUG),1)
PRODUCT_SYSTEM_PROPERTIES += \
    ro.adb.secure=0 \
    persist.sys.usb.config=adb
endif

# Restart with the cable plugged in: boot Android instead of the black charging screen
PRODUCT_COPY_FILES += \
    vendor/noxis/config/init/noxis-charger.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/noxis-charger.rc

# ------------------------------------------------------------ Speed (flagship feel)
# Compile the apps you touch all the time fully ahead of time ("speed") instead of
# only the profiled hot paths: no JIT warm-up, smoother first scrolls and launches.
# SystemUI and the launcher are already "speed" in LineageOS.
PRODUCT_DEXPREOPT_SPEED_APPS += \
    Settings \
    TrebuchetQuickStep \
    Launcher3QuickStep \
    NoxisGuard
# system_server fully compiled: snappier app switching, notifications, permission dialogs
PRODUCT_SYSTEM_SERVER_COMPILER_FILTER := speed

PRODUCT_SYSTEM_PROPERTIES += \
    dalvik.vm.boot-dex2oat-threads=8 \
    dalvik.vm.boot-dex2oat-cpu-set=0,1,2,3,4,5,6,7 \
    dalvik.vm.dex2oat-threads=8 \
    dalvik.vm.dex2oat-cpu-set=0,1,2,3,4,5,6,7 \
    dalvik.vm.madvise.vdexfile.size=104857600 \
    dalvik.vm.madvise.odexfile.size=104857600 \
    dalvik.vm.madvise.artfile.size=4294967295
# boot-dex2oat/dex2oat on all 8 cores: first boot after an OTA and app installs finish
# faster. Background optimisation (while charging) stays on the small cores (battery).
# madvise: app code is read ahead in one go -> faster cold starts.
