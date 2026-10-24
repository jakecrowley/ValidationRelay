#!/usr/bin/env bash
set -euo pipefail

THEOS_DIR="${THEOS:-$HOME/theos}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> [1/6] Installing Arch Linux prerequisites..."
sudo pacman -S --needed base-devel git perl curl rsync zstd xz libxml2-legacy zip

echo "==> [2/6] Setting up Theos in $THEOS_DIR..."
if [ ! -d "$THEOS_DIR" ]; then
    git clone --recursive https://github.com/theos/theos.git "$THEOS_DIR"
else
    echo "    Theos already exists at $THEOS_DIR"
fi

echo "==> [3/6] Installing Swift 5.8 iOS Cross-Toolchain (kabiroberai/swift-toolchain-linux)..."
mkdir -p "$THEOS_DIR/toolchain"
if [ ! -f "$THEOS_DIR/toolchain/linux/iphone/bin/swiftc" ]; then
    TOOLCHAIN_URL="https://github.com/kabiroberai/swift-toolchain-linux/releases/download/v2.3.0/swift-5.8-ubuntu22.04.tar.xz"
    echo "    Downloading $TOOLCHAIN_URL ..."
    curl -fL "$TOOLCHAIN_URL" | tar -xJf - -C "$THEOS_DIR/toolchain/"
else
    echo "    Swift cross-toolchain already installed at $THEOS_DIR/toolchain/linux/iphone"
fi

echo "==> [4/6] Checking Arch Linux shared library compatibility for Ubuntu 22.04 Swift binary..."
for LIB_DIR in "$THEOS_DIR/toolchain/linux/host/lib" "$THEOS_DIR/toolchain/linux/iphone/lib"; do
    mkdir -p "$LIB_DIR"
    [ -e /usr/lib/libedit.so.0 ]     && ln -sf /usr/lib/libedit.so.0     "$LIB_DIR/libedit.so.2"
    [ -e /usr/lib/libncursesw.so.6 ] && ln -sf /usr/lib/libncursesw.so.6 "$LIB_DIR/libncurses.so.6"
    [ -e /usr/lib/libpanelw.so.6 ]   && ln -sf /usr/lib/libpanelw.so.6   "$LIB_DIR/libpanel.so.6"
    [ -e /usr/lib/libformw.so.6 ]    && ln -sf /usr/lib/libformw.so.6    "$LIB_DIR/libform.so.6"
    [ -e /usr/lib/libmenuw.so.6 ]    && ln -sf /usr/lib/libmenuw.so.6    "$LIB_DIR/libmenu.so.6"
done

echo "==> [5/6] Installing matching iPhoneOS16.5.sdk (Swift 5.8)..."
mkdir -p "$THEOS_DIR/sdks"
if [ ! -d "$THEOS_DIR/sdks/iPhoneOS16.5.sdk" ]; then
    TMP_SDK="$(mktemp -d)"
    git clone --depth=1 https://github.com/theos/sdks.git "$TMP_SDK"
    cp -r "$TMP_SDK/iPhoneOS16.5.sdk" "$THEOS_DIR/sdks/"
    rm -rf "$TMP_SDK"
else
    echo "    iPhoneOS16.5.sdk already exists in $THEOS_DIR/sdks"
fi

echo "==> [6/6] Fetching vendor dependency (NWWebSocket)..."
"$SCRIPT_DIR/fetch_vendor.sh"

echo ""
echo "==> Testing Swift Cross-Compiler..."
"$THEOS_DIR/toolchain/linux/iphone/bin/swiftc" --version

echo ""
echo "=========================================================="
echo " Setup Complete!"
echo " Run the following to build ValidationRelay.tipa:"
echo "   export THEOS=$THEOS_DIR"
echo "   make"
echo "=========================================================="
