**Sep 20, 2026**: Android 13 support + runtime driver switching

**Magisk, KernelSU, and APatch supported**

**Requires Android 13 (SDK 33) to install**

1. Lowered the build target to platform SDK 33, so the module installs and runs
   on Android 13 devices (Retroid Pocket 5 and friends). The same binary still
   runs on Android 14/15/16.
2. The driver is now installed as `vulkan.turnip.so` **alongside** the stock
   `vulkan.adreno.so` instead of replacing it.
3. Added runtime driver switching via the module action button - toggles
   `ro.hardware.vulkan` between `turnip` and the stock driver. No reboot, no
   reflash; takes effect for newly launched apps.
4. The selected driver is persisted and re-applied on every boot
   (`post-fs-data.sh`), and preserved across module updates.
5. The stock driver name is auto-detected at install time by walking the Vulkan
   loader's fallback chain, so switching back works on devices that don't set
   `ro.hardware.vulkan`.
6. Added `system.prop` with `debug.hwui.renderer=skiagl` to keep the system UI
   off Turnip.
7. Build now fails early with a clear message if the NDK has dropped the target
   API level.

---

**Sep 19, 2026**: Updated Mesa to v26.2.3

**Magisk, KernelSU, and APatch supported**

**Requires Android 14 to install**

1. Updated Mesa to v26.2.3
2. Updated Android NDK to stable r30
3. Fixed SELinux context for vulkan driver (`same_process_hal_file`)
4. Optimized GPU Cache Cleaner to single-pass targeted traversal (fixes installer freezes)
5. Added cache cleanup on module uninstallation
6. Added DT_SONAME patching and symbol stripping (`llvm-strip`)
7. Fixed module installer compatibility and syntax checks

---

**Aug 14, 2026**: Updated Mesa to v26.2.0

Turnip drivers from now on will be delayed as I no longer have time / interest to maintain this.

I will try to keep this project up to date as much as I can.

**Magisk and KernelSU supported**

**Requires Android 14 to install**

1. Updated Android NDK to 30 beta2
2. LTO support removed to fix issues when building Mesa 26.2.0
3. Added uninstall script and minor improvements
4. Updated minimum Magisk version to v25.0
5. Now supports auto-updates via Magisk / KernelSU
6. GPU Cache Cleaner is now included in MAGISK / KSU builds (no manual cleanup needed)
