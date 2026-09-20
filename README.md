# Freedreno Turnip Builder

### Stable Mesa + Android NDK (r30) - Android 13+ with runtime driver switching

Simple Bash script to build Turnip Vulkan drivers for Magisk, KernelSU and Android Emulators.

The root module installs Turnip **alongside** the stock Adreno driver instead of
overwriting it, so you can switch between the two from the module's action button
without reflashing anything.

## What's New

See the latest changes in [UPDATES.md](UPDATES.md) or grab prebuilts from [Releases](../../releases).

## Switching Drivers

The module ships the driver as `vulkan.turnip.so` and selects it through the
`ro.hardware.vulkan` system property, which is what Android's Vulkan loader uses
to decide which `/vendor/lib64/hw/vulkan.*.so` to load. Your stock
`vulkan.adreno.so` is never touched.

Tap the **action button** on the module card in Magisk / KernelSU / APatch:

```
Turnip  <->  stock Adreno
```

- Takes effect for **newly launched** apps - no reboot needed.
- Already-running apps keep the driver they started with.
- The choice is remembered across reboots.
- Turnip is selected by default after the first install.

From a shell (adb / Termux) the same toggle is:

```bash
su -c 'sh /data/adb/modules/turnip-mesa/action.sh'
```

Check which driver is active at any time:

```bash
getprop ro.hardware.vulkan     # "turnip" or your stock value (usually "adreno")
```

If a game misbehaves on Turnip, flip back to stock and relaunch it - no need to
uninstall the module.

## How to Build Locally

Clone the repository and run the build script:

```bash
bash build-turnip.sh
```

Check the [Notes](#notes) section below for prerequisites.

## App Compatibility

| Name | Status | Notes |
|---|:---:|---|
| 3DMark | Working | |
| GRID™ Autosport | Working | Tested by [@V3KT0R-87](https://github.com/V3KT0R-87)<br>60 fps |
| SpongeBob SquarePants Battle For Bikini Bottom | Working | Tested by [@V3KT0R-87](https://github.com/V3KT0R-87)<br>30 - 45 fps |
| CarX Street | Working | Tested by [@V3KT0R-87](https://github.com/V3KT0R-87)<br>30 - 45 fps |
| Dolphin Emulator | Working | Tested by [@V3KT0R-87](https://github.com/V3KT0R-87) |
| PPSSPP | Working | Tested by [@V3KT0R-87](https://github.com/V3KT0R-87) |
| EggNS | Working | Tested by [@V3KT0R-87](https://github.com/V3KT0R-87) |
| ANGLE (com.android.angle) | Working | |
| GTA Trilogy - Definitive Edition | Working | Tested by [@Ryder_7777](https://t.me/Ryder_7777)<br>Poor performance |
| Call of Duty: Warzone Mobile | Working | Tested by [@SeniorFurry](https://t.me/SeniorFurry)<br>Texture bugs, poor performance |
| Hitman: Blood Money – Reprisal | Working | Tested by [@V3KT0R-87](https://github.com/V3KT0R-87)<br>60 fps, medium graphics |

## Notes

- Requires **Android 13+ (SDK 33+)** to install the root module. The driver is
  built against platform SDK 33 and still runs on Android 14/15/16.
- **Important:** Android 15 (SDK 35) is needed for full Vulkan 1.4 support. On
  Android 13/14 the platform loader caps the exposed API at Vulkan 1.3
  regardless of what the driver supports.
- The action button needs Magisk v27+, KernelSU 0.9.5+, or APatch. On older
  root solutions use the `action.sh` shell command above instead.
- Supports Magisk v25.2+, KernelSU, and APatch.
- Recommended build environment: Ubuntu 24.04 / 26.04 or any compatible Linux distribution.
- Ensure a stable internet connection for downloading the Android NDK and Mesa source.

## Credits

This project wouldn't be possible without the help of these people:

- [@v3kt0r-87](https://github.com/v3kt0r-87) for the upstream build script this fork is based on.
- [@MrMiy4mo](https://github.com/ilhan-athn7) for creating the Turnip build script and letting me modify and learn from it.
- [@Mesa3D Team](https://gitlab.freedesktop.org/mesa/mesa) for the graphics driver stack.
- [Adreno Driver Support Group](https://t.me/adreno_driver) for testing and sharing benchmarks.
