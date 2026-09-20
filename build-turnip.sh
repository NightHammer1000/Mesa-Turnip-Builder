#!/bin/bash -e

# Define colors for terminal output
green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

# Define Android NDK version and download URL
ndkdir="android-ndk-r30"
ndkver="https://dl.google.com/android/repository/${ndkdir}-linux.zip"

# Target platform SDK level.
# 33 = Android 13. Built against 33 the driver still runs on 14/15/16, so this
# is the widest-compatibility target. Do not raise it without dropping A13.
sdkver="33"

# Define Mesa version and download URL
mesa_version="26.2.3"
mesadir="mesa-mesa-${mesa_version}"
mesaver="https://gitlab.freedesktop.org/mesa/mesa/-/archive/mesa-${mesa_version}/mesa-mesa-${mesa_version}.zip?ref_type=tags"

# Module identity
modid="turnip-mesa"
modversioncode="20260920"
updatejson="https://raw.githubusercontent.com/NightHammer1000/Mesa-Turnip-Builder/refs/heads/stable/update.json"

# Define working directories
workdir="$(pwd)/turnip_workdir"         # Base directory for all operations
magiskdir="$workdir/turnip_module"      # Directory to create the Magisk module

DRIVER_FILE="vulkan.turnip.so"          # Output Vulkan Driver (module + emulator)
META_FILE="meta.json"                   # Metadata

ZIP_FILE_MAGISK="Turnip-${mesa_version}-MAGISK-KSU.zip"
ZIP_FILE_EMULATOR="Turnip-${mesa_version}-EMULATOR.zip"

# List of required packages to build the Turnip driver
deps="meson ninja patchelf unzip curl flex bison zip clang ccache pkg-config"
[ -t 1 ] && clear || true

echo "Checking system for required dependencies..."

# Check for required dependencies
for deps_chk in $deps; do

    [ -t 1 ] && sleep 0.25 || true
    if command -v "$deps_chk" >/dev/null 2>&1; then
        if [ "$deps_chk" = "meson" ]; then
            meson_ver=$(meson --version 2>/dev/null || echo "0")
            if [ "$(printf '%s\n' "1.4.0" "$meson_ver" | sort -V | head -n1)" != "1.4.0" ]; then
                echo -e "$red - meson found ($meson_ver), but >= 1.4.0 is required. Upgrade with: pip3 install --upgrade --break-system-packages meson $nocolor"
                deps_missing=1
            else
                echo -e "$green - meson found ($meson_ver) $nocolor"
            fi
        else
            echo -e "$green - $deps_chk found $nocolor"
        fi
    else
        echo -e "$red - $deps_chk not found, cannot continue. $nocolor"
        deps_missing=1
    fi
done

if [ "${deps_missing:-0}" = "1" ]; then
    echo -e "$red Missing or outdated dependencies. Please install them and try again. $nocolor"
    exit 1
fi

[ -t 1 ] && sleep 1 || true
[ -t 1 ] && clear || true

# Clean work directory if it exists
if [ -d "$workdir" ]; then
    echo "Work directory already exists. Cleaning before proceeding..." $'\n'
    rm -rf "$workdir"
    sleep 2
fi

echo "Creating and entering the work directory..." $'\n'
mkdir -p "$workdir" && cd "$_"

# Download Android NDK
echo "Downloading Android NDK..." $'\n'
curl -sSL --fail "$ndkver" --output "$ndkdir".zip

[ -t 1 ] && clear || true

echo "Extracting Android NDK..." $'\n'
unzip "$ndkdir".zip &> /dev/null
rm -f "$ndkdir".zip

# Download Mesa source
echo "Downloading Latest Mesa source ..." $'\n'
curl -sSL --fail "$mesaver" --output "$mesadir".zip

[ -t 1 ] && clear || true

echo "Extracting Mesa source..." $'\n'
unzip "$mesadir".zip &> /dev/null
rm -f "$mesadir".zip
cd $mesadir

# Set NDK Clang bin directory
ndk_bin="$workdir/$ndkdir/toolchains/llvm/prebuilt/linux-x86_64/bin"

# Make sure this NDK still ships a wrapper for the target API level. NDKs drop
# support for old API levels over time; fail here with a clear message instead
# of somewhere deep inside meson.
if [ ! -x "$ndk_bin/aarch64-linux-android$sdkver-clang" ]; then
    echo -e "$red $ndkdir does not provide aarch64-linux-android$sdkver-clang. $nocolor"
    echo -e "$red This NDK no longer supports API $sdkver - pin an older NDK or raise \$sdkver. $nocolor"
    echo "API levels available in this NDK:"
    ls "$ndk_bin" | grep -o 'aarch64-linux-android[0-9]*-clang$' | sort -u
    exit 1
fi

# Set toolchain variables
export CC=clang
export CXX=clang++
export AR=llvm-ar
export RANLIB=llvm-ranlib
export STRIP=llvm-strip
export OBJDUMP=llvm-objdump
export OBJCOPY=llvm-objcopy
export LDFLAGS="-fuse-ld=lld"

# Create a temporary directory for fake cc/c++
fakecc_dir="$workdir/fake-cc"
mkdir -p "$fakecc_dir"

# Create symbolic links to NDK-Clang
ln -sf "$ndk_bin/clang" "$fakecc_dir/cc"
ln -sf "$ndk_bin/clang++" "$fakecc_dir/c++"

# Prepend both fake-cc and NDK bin to PATH
export PATH="$fakecc_dir:$ndk_bin:$PATH"

echo "Creating Meson cross file..." $'\n'

cat <<EOF >"android-aarch64.txt"
[binaries]
ar = '$ndk_bin/llvm-ar'
c = ['ccache', '$ndk_bin/aarch64-linux-android$sdkver-clang', '-Wno-deprecated-declarations', '-Wno-gnu-alignof-expression']
cpp = ['ccache', '$ndk_bin/aarch64-linux-android$sdkver-clang++', '--start-no-unused-arguments', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '-static-libstdc++', '--end-no-unused-arguments', '-Wno-error=c++11-narrowing', '-Wno-deprecated-declarations', '-Wno-gnu-alignof-expression']
c_ld = '$ndk_bin/ld.lld'
cpp_ld = '$ndk_bin/ld.lld'
strip = '$ndk_bin/llvm-strip'
pkg-config = ['env', 'PKG_CONFIG_LIBDIR=NDKDIR/pkg-config', '/usr/bin/pkg-config']

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

cat <<EOF >"native.txt"
[build_machine]
c = ['ccache', 'clang']
cpp = ['ccache', 'clang++']
ar = 'llvm-ar'
strip = 'llvm-strip'
c_ld = 'ld.lld'
cpp_ld = 'ld.lld'
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

echo "Generating build files (target API $sdkver)..." $'\n'
if ! CC=clang CXX=clang++ meson setup build-android-aarch64 \
    --cross-file "$workdir/$mesadir/android-aarch64.txt" \
    --native-file "$workdir/$mesadir/native.txt" \
    -Dbuildtype=release \
    -Dplatforms=android \
    -Dplatform-sdk-version="$sdkver" \
    -Dandroid-stub=true \
    -Dandroid-libbacktrace=disabled \
    -Dgallium-drivers= \
    -Dvulkan-drivers=freedreno \
    -Dfreedreno-kmds=kgsl \
    -Degl=disabled \
    -Dstrip=true &> "$workdir/meson_log"; then
    echo -e "$red Meson setup failed! Log: $nocolor"
    cat "$workdir/meson_log"
    exit 1
fi

# Compile build files using Ninja
echo "Compiling build files..." $'\n'
if ! ninja -C build-android-aarch64 &> "$workdir"/ninja_log; then
    echo -e "$red Ninja compilation failed! Log: $nocolor"
    cat "$workdir/ninja_log"
    exit 1
fi

echo "Stripping and patching driver binaries..." $'\n'
driver_src="$workdir/$mesadir/build-android-aarch64/src/freedreno/vulkan/libvulkan_freedreno.so"
if [ ! -f "$driver_src" ]; then
    echo -e "$red Build failed! libvulkan_freedreno.so not found at $driver_src $nocolor" && exit 1
fi

cp "$driver_src" "$workdir/libvulkan_freedreno.so"
cd "$workdir"

# Strip unneeded debug symbols to reduce size from ~60MB+ to ~15-20MB
"$ndk_bin/llvm-strip" --strip-unneeded libvulkan_freedreno.so

# One driver file for both the root module and the emulator package. It is
# installed *alongside* the stock vulkan.adreno.so (never over it), so the
# stock driver stays available for runtime switching.
cp libvulkan_freedreno.so "$DRIVER_FILE"

# Set DT_SONAME using patchelf to match the driver filename
patchelf --set-soname "$DRIVER_FILE" "$DRIVER_FILE"

echo "Prepare magisk module structure..." $'\n'
p1="system/vendor/lib64/hw"
mkdir -p "$magiskdir/$p1"
cp "$workdir/$DRIVER_FILE" "$magiskdir/$p1/"
cd "$magiskdir"

meta="META-INF/com/google/android"
mkdir -p "$meta"

# Create update-binary
cat <<'EOF' >"$meta/update-binary"
#!/sbin/sh

#################
# Initialization
#################

umask 022

# echo before loading util_functions
ui_print() { echo "$1"; }

require_new_magisk() {
  ui_print "*******************************"
  ui_print " Please install Magisk v25.2+! "
  ui_print "*******************************"
  exit 1
}

#########################
# Load util_functions.sh
#########################

OUTFD=$2
ZIPFILE=$3

mount /data 2>/dev/null

if [ -f /data/adb/magisk/util_functions.sh ]; then
  . /data/adb/magisk/util_functions.sh
elif [ -f /data/adb/ksu/util_functions.sh ]; then
  . /data/adb/ksu/util_functions.sh
elif [ -f /data/adb/ap/util_functions.sh ]; then
  . /data/adb/ap/util_functions.sh
else
  require_new_magisk
fi

[ -n "$MAGISK_VER_CODE" ] && [ "$MAGISK_VER_CODE" -lt 25200 ] && require_new_magisk

install_module
exit 0
EOF

# Create updater-script
cat <<'EOF' >"$meta/updater-script"
#MAGISK
EOF

###############################################################################
# common.sh - shared helpers for customize.sh / post-fs-data.sh / action.sh
#
# Android's Vulkan loader resolves the driver by reading, in order:
#   ro.hardware.vulkan, ro.hardware, ro.product.board, ro.board.platform, ro.arch
# and dlopen()ing /vendor/lib64/hw/vulkan.<value>.so
#
# So shipping the driver as vulkan.turnip.so and flipping ro.hardware.vulkan
# switches drivers at runtime without ever touching vulkan.adreno.so.
###############################################################################
cat <<'EOF' >"common.sh"
#!/system/bin/sh

HWDIRS="/vendor/lib64/hw /system/vendor/lib64/hw"

# resetprop lives in a different place on each root solution
rp() {
    if command -v resetprop >/dev/null 2>&1; then
        resetprop "$@"
    elif [ -x /data/adb/magisk/resetprop ]; then
        /data/adb/magisk/resetprop "$@"
    elif [ -x /data/adb/magisk/magisk ]; then
        /data/adb/magisk/magisk resetprop "$@"
    elif [ -x /data/adb/ksu/bin/resetprop ]; then
        /data/adb/ksu/bin/resetprop "$@"
    elif [ -x /data/adb/ap/bin/resetprop ]; then
        /data/adb/ap/bin/resetprop "$@"
    else
        return 1
    fi
}

# hal_lib_exists <name>  ->  true if vulkan.<name>.so is present on the device
hal_lib_exists() {
    [ -n "$1" ] || return 1
    for d in $HWDIRS; do
        [ -f "$d/vulkan.$1.so" ] && return 0
    done
    return 1
}

# apply_vulkan_hal <name>
# An empty name deletes the property, which makes the loader fall back to
# ro.hardware / ro.board.platform exactly as it did before this module existed.
apply_vulkan_hal() {
    if [ -z "$1" ]; then
        rp --delete ro.hardware.vulkan
    else
        rp ro.hardware.vulkan "$1"
    fi
}

# Walk the loader's fallback chain looking for a driver that actually exists,
# so we know what to switch back to. Never returns "turnip".
detect_stock_hal() {
    for cand in "$(getprop ro.hardware.vulkan)" adreno \
                "$(getprop ro.hardware)" \
                "$(getprop ro.product.board)" \
                "$(getprop ro.board.platform)"; do
        [ -z "$cand" ] && continue
        [ "$cand" = "turnip" ] && continue
        if hal_lib_exists "$cand"; then
            echo "$cand"
            return 0
        fi
    done
    echo ""
}
EOF

###############################################################################
# post-fs-data.sh - re-applies the persisted driver choice on every boot
###############################################################################
cat <<EOF >"post-fs-data.sh"
#!/system/bin/sh
MODDIR=\${0%/*}
[ -d "\$MODDIR" ] || MODDIR=/data/adb/modules/$modid
. "\$MODDIR/common.sh"

MODE=turnip
[ -f "\$MODDIR/driver_mode" ] && MODE=\$(cat "\$MODDIR/driver_mode")

if [ "\$MODE" = "stock" ]; then
    STOCK=""
    [ -f "\$MODDIR/stock_vulkan_hal" ] && STOCK=\$(cat "\$MODDIR/stock_vulkan_hal")
    apply_vulkan_hal "\$STOCK"
else
    apply_vulkan_hal turnip
fi
EOF

###############################################################################
# action.sh - Magisk / KernelSU / APatch action button: toggle the driver
###############################################################################
cat <<EOF >"action.sh"
#!/system/bin/sh
MODDIR=\${0%/*}
[ -d "\$MODDIR" ] || MODDIR=/data/adb/modules/$modid
. "\$MODDIR/common.sh"

STOCK=""
[ -f "\$MODDIR/stock_vulkan_hal" ] && STOCK=\$(cat "\$MODDIR/stock_vulkan_hal")

CURRENT=\$(getprop ro.hardware.vulkan)

if [ "\$CURRENT" = "turnip" ]; then
    if apply_vulkan_hal "\$STOCK"; then
        echo stock > "\$MODDIR/driver_mode"
        if [ -n "\$STOCK" ]; then
            echo "Switched to: stock driver (vulkan.\$STOCK.so)"
        else
            echo "Switched to: stock driver (ro.hardware.vulkan cleared)"
        fi
    else
        echo "ERROR: resetprop not available - cannot switch."
    fi
else
    if apply_vulkan_hal turnip; then
        echo turnip > "\$MODDIR/driver_mode"
        echo "Switched to: Turnip (Mesa $mesa_version)"
    else
        echo "ERROR: resetprop not available - cannot switch."
    fi
fi

echo ""
echo "ro.hardware.vulkan = \$(getprop ro.hardware.vulkan)"
echo ""
echo "Takes effect for newly launched apps."
echo "Already-running apps keep the old driver until restarted."
echo "The choice is remembered across reboots."
sleep 5
EOF

cat <<'EOF' >"uninstall.sh"
#!/system/bin/sh
find /data/user/*/*/*cache /data/data/*/*cache /data/user_de/*/*/*cache -mindepth 1 -maxdepth 3 \
    \( -iname "*shader*" -o -iname "*graphitecache*" -o -iname "*gpucache*" \) \
    -exec rm -rf {} + 2>/dev/null || true
EOF

# Keep the UI renderer on GL. Turnip is meant for apps/games here; letting
# HWUI (SystemUI, launcher) run on it is the usual cause of boot loops.
cat <<'EOF' >"system.prop"
debug.hwui.renderer=skiagl
EOF

cat <<EOF >"module.prop"
id=$modid
name=Freedreno Turnip Vulkan Driver STABLE
version=v$mesa_version (SDK $sdkver)
versionCode=$modversioncode
author=V3KT0R-87, N1GHT
description=Turnip open-source Vulkan driver for Adreno 6xx-8xx GPUs. Installed alongside the stock driver - tap the action button to switch between Turnip and stock.
updateJson=$updatejson
EOF

cat <<EOF >"customize.sh"
. \$MODPATH/common.sh

OLDDIR=/data/adb/modules/$modid

MODVER=\$(grep_prop version \$MODPATH/module.prop)
MODVERCODE=\$(grep_prop versionCode \$MODPATH/module.prop)

ui_print ""
ui_print "Version=\$MODVER "
ui_print "MagiskVersion=\$MAGISK_VER"
ui_print ""
ui_print "Freedreno Turnip Vulkan Driver -V3KT0R"
ui_print "Runtime driver switching -N1GHT"
ui_print "Adreno Driver Support Group - Telegram"
ui_print ""
sleep 1.25

ui_print ""
ui_print "Checking Device info ..."
sleep 1.25

SDK_VER=\$(getprop ro.build.version.sdk)
[ -z "\$SDK_VER" ] && SDK_VER=\$(getprop ro.system.build.version.sdk)
[ "\${SDK_VER:-0}" -lt $sdkver ] && abort "Android 13 (SDK $sdkver) or newer is required! Aborting ..."

ui_print "- Android SDK \$SDK_VER"
ui_print "- Board: \$(getprop ro.board.platform)"

# Work out what the stock driver is, so the action button can switch back to
# it. On a reinstall ro.hardware.vulkan already reads "turnip", so reuse the
# value saved by the previous install before probing.
STOCK=""
if [ -f "\$OLDDIR/stock_vulkan_hal" ]; then
    STOCK=\$(cat "\$OLDDIR/stock_vulkan_hal")
else
    STOCK=\$(detect_stock_hal)
fi
echo "\$STOCK" > \$MODPATH/stock_vulkan_hal

if [ -n "\$STOCK" ]; then
    ui_print "- Stock Vulkan driver: vulkan.\$STOCK.so"
else
    ui_print "- Stock Vulkan driver: not detected"
    ui_print "  (switching back clears ro.hardware.vulkan)"
fi

# Preserve the user's driver choice across module updates
if [ -f "\$OLDDIR/driver_mode" ]; then
    cp "\$OLDDIR/driver_mode" \$MODPATH/driver_mode
    ui_print "- Keeping driver selection: \$(cat \$MODPATH/driver_mode)"
else
    echo turnip > \$MODPATH/driver_mode
fi

ui_print ""
ui_print "Everything looks fine .... proceeding"
ui_print ""
ui_print "Installing Driver Please Wait ..."
ui_print ""

sleep 1.25
set_perm_recursive \$MODPATH/system 0 0 0755 0644
set_perm \$MODPATH/system/vendor/lib64/hw/$DRIVER_FILE 0 0 0644 u:object_r:same_process_hal_file:s0
set_perm \$MODPATH/common.sh 0 0 0644
set_perm \$MODPATH/post-fs-data.sh 0 0 0755
set_perm \$MODPATH/action.sh 0 0 0755
set_perm \$MODPATH/uninstall.sh 0 0 0755

ui_print ""
ui_print " Cleaning GPU Cache ... Please wait!"
find /data/user/*/*/*cache /data/data/*/*cache /data/user_de/*/*/*cache -mindepth 1 -maxdepth 3 \\
    \\( -iname "*shader*" -o -iname "*graphitecache*" -o -iname "*gpucache*" \\) \\
    -exec rm -rf {} + 2>/dev/null || true

ui_print ""
ui_print "- GPU Cache Cleared ..."
ui_print ""

ui_print "Driver installed Successfully"
sleep 1.25

ui_print ""
ui_print "The stock driver was NOT replaced."
ui_print "Tap the module's action button to switch:"
ui_print "  Turnip  <->  stock Adreno"
ui_print ""
ui_print "REBOOT is required before first use."
ui_print ""
ui_print "BY: @VEKT0R_87 / @N1GHT"
ui_print ""
EOF

echo "Packing driver files into Magisk/KSU module ..." $'\n'

chmod 0755 "$meta/update-binary"
chmod 0755 customize.sh
chmod 0755 uninstall.sh
chmod 0755 action.sh
chmod 0755 post-fs-data.sh
chmod 0644 common.sh

zip -r "$workdir/$ZIP_FILE_MAGISK" * &> /dev/null

if [[ ! -f "$workdir/$ZIP_FILE_MAGISK" ]]; then
    echo -e "${red}Error: Zipping driver files failed.${nocolor}"
    exit 1
else
    [ -t 1 ] && clear || true

    echo " Its time to create Turnip build for EMULATOR"

    sleep 2

    cd "$workdir"

# Create meta.json file for turnip emulator
 cat <<EOF > "$META_FILE"
{
  "schemaVersion": 1,
  "name": "Freedreno Turnip Driver $mesa_version",
  "description": "Compiled using Android NDK 30 (API $sdkver)",
  "author": "v3kt0r-87",
  "packageVersion": "3",
  "vendor": "Mesa3D",
  "driverVersion": "Vulkan 1.3/4",
  "minApi": $sdkver,
  "libraryName": "$DRIVER_FILE"
}
EOF

# Zip the turnip .so file and meta.json file
    if ! zip "$workdir/$ZIP_FILE_EMULATOR" "$DRIVER_FILE" "$META_FILE" &> /dev/null; then
        echo -e "${red}Error: Zipping driver files failed.${nocolor}"
        exit 1
    fi

    [ -t 1 ] && clear || true

    echo -e "$green Build Finished :). $nocolor" $'\n'
    echo -e "$green-All done, you can take your drivers from here:$nocolor" $'\n'
    echo -e "Magisk-KSU Module : $workdir/$ZIP_FILE_MAGISK" $'\n'
    echo -e "Emulator : $workdir/$ZIP_FILE_EMULATOR" $'\n'
    echo -e "Turnip Driver : $workdir/$DRIVER_FILE" $'\n'

    # Cleanup
    rm -f "$META_FILE"

    # Clean up fake-cc directory and symbolic links on exit
    rm -rf "$fakecc_dir"

fi
