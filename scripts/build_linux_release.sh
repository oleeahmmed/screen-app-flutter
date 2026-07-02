#!/usr/bin/env bash
# Build AIMS for Debian/Ubuntu and create distributable packages.
#
# Usage:
#   bash scripts/build_linux_release.sh
#   API_ORIGIN=https://aims.igenhr.com bash scripts/build_linux_release.sh
#   bash scripts/build_linux_release.sh --skip-apt
#
# Output (in dist/):
#   aims-linux-<arch>-<version>.tar.gz   — portable bundle
#   aims_<version>_<deb-arch>.deb        — Debian/Ubuntu installer

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Use user-space toolchain/sysroot when present (no sudo required).
if [[ -f "$ROOT/scripts/linux_build_env.sh" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT/scripts/linux_build_env.sh" || true
fi

API_ORIGIN="${API_ORIGIN:-https://aims.igenhr.com}"
SKIP_APT=false
BUILD_DEB=true
BUILD_TAR=true

for arg in "$@"; do
  case "$arg" in
    --skip-apt) SKIP_APT=true ;;
    --deb-only) BUILD_TAR=false ;;
    --tar-only) BUILD_DEB=false ;;
    --help|-h)
      echo "Usage: bash scripts/build_linux_release.sh [--skip-apt] [--deb-only] [--tar-only]"
      echo "  API_ORIGIN=<url>  override backend (default: https://aims.igenhr.com)"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      exit 1
      ;;
  esac
done

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
BUILD_NUMBER="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f2)"
DIST="$ROOT/dist"
PKG_ID="com.igenhr.aims"
INSTALL_DIR="/opt/aims"

case "$(uname -m)" in
  x86_64)
    DEB_ARCH="amd64"
    FLUTTER_ARCH="x64"
    ;;
  aarch64|arm64)
    DEB_ARCH="arm64"
    FLUTTER_ARCH="arm64"
    ;;
  *)
    echo "ERROR: Unsupported CPU architecture: $(uname -m)"
    exit 1
    ;;
esac

OUT_NAME="aims-linux-${DEB_ARCH}-${VERSION}"
BUNDLE="$ROOT/build/linux/${FLUTTER_ARCH}/release/bundle"
DEB_FILE="$DIST/aims_${VERSION}_${DEB_ARCH}.deb"

echo "==> AIMS Linux release (v${VERSION}+${BUILD_NUMBER}, ${DEB_ARCH})"
echo "    API_ORIGIN=$API_ORIGIN"

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: Flutter not found. Install Flutter first:"
  echo "  https://docs.flutter.dev/get-started/install/linux"
  exit 1
fi

echo "==> Checking Flutter Linux support..."
flutter config --enable-linux-desktop >/dev/null 2>&1 || true
flutter doctor -v

if [[ "$SKIP_APT" == false ]] && command -v apt-get >/dev/null 2>&1; then
  echo "==> Installing build dependencies (Debian/Ubuntu)..."
  if command -v sudo >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y \
      clang cmake ninja-build pkg-config \
      libgtk-3-dev libblkid-dev liblzma-dev \
      libsecret-1-dev libjsoncpp-dev \
      libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
      dpkg-dev
  else
    apt-get update -qq
    apt-get install -y \
      clang cmake ninja-build pkg-config \
      libgtk-3-dev libblkid-dev liblzma-dev \
      libsecret-1-dev libjsoncpp-dev \
      libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
      dpkg-dev
  fi
fi

echo "==> flutter pub get"
flutter pub get

echo "==> flutter build linux --release"
flutter build linux --release --dart-define=API_ORIGIN="$API_ORIGIN"

if [[ ! -d "$BUNDLE" ]]; then
  echo "ERROR: Expected bundle at $BUNDLE"
  exit 1
fi

mkdir -p "$DIST"

if [[ "$BUILD_TAR" == true ]]; then
  echo "==> Creating portable .tar.gz..."
  STAGE="$DIST/$OUT_NAME"
  rm -rf "$STAGE"
  cp -a "$BUNDLE" "$STAGE"

  cat > "$STAGE/run-aims.sh" <<'EOF'
#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/aims" "$@"
EOF
  chmod +x "$STAGE/run-aims.sh" "$STAGE/aims"

  cat > "$STAGE/INSTALL.txt" <<EOF
AIMS Linux (v${VERSION})
======================

Quick start
-----------
1. Extract this folder anywhere, e.g. ~/Applications/aims
2. Run:
     ./run-aims.sh
   or:
     ./aims

Optional: desktop shortcut
--------------------------
Copy aims.desktop to ~/.local/share/applications/ then set Exec= and Icon= paths.

Screenshot capture (optional, for clock-in monitoring)
--------------------------------------------------------
Install one of:
  sudo apt install gnome-screenshot
  sudo apt install grim        # Wayland
  sudo apt install scrot maim  # alternatives

System libraries (Ubuntu/Debian desktop)
------------------------------------------
  sudo apt install libgtk-3-0 libsecret-1-0 libgstreamer1.0-0

Optional — chat voice playback on Linux
---------------------------------------
  sudo apt install gstreamer1.0-plugins-base gstreamer1.0-plugins-good
EOF

  cat > "$STAGE/aims.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=AIMS
Comment=iGenHR client
Exec=PLACEHOLDER/aims
Icon=PLACEHOLDER/data/flutter_assets/assets/branding/logo.png
Terminal=false
Categories=Office;
StartupWMClass=aims
EOF

  ARCHIVE="$DIST/${OUT_NAME}.tar.gz"
  rm -f "$ARCHIVE"
  tar -czf "$ARCHIVE" -C "$DIST" "$OUT_NAME"
  echo "    Archive: $ARCHIVE"
fi

if [[ "$BUILD_DEB" == true ]]; then
  echo "==> Creating .deb package..."
  if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "ERROR: dpkg-deb not found. Install: sudo apt install dpkg-dev"
    exit 1
  fi

  PKGROOT="$(mktemp -d)"
  trap 'rm -rf "$PKGROOT"' EXIT

  mkdir -p "$PKGROOT/DEBIAN"
  mkdir -p "$PKGROOT$INSTALL_DIR"
  mkdir -p "$PKGROOT/usr/bin"
  mkdir -p "$PKGROOT/usr/share/applications"
  mkdir -p "$PKGROOT/usr/share/icons/hicolor/256x256/apps"
  mkdir -p "$PKGROOT/usr/share/icons/hicolor/128x128/apps"

  cp -a "$BUNDLE/." "$PKGROOT$INSTALL_DIR/"
  chmod 755 "$PKGROOT$INSTALL_DIR/aims"

  cat > "$PKGROOT/usr/bin/aims" <<EOF
#!/bin/sh
exec ${INSTALL_DIR}/aims "\$@"
EOF
  chmod 755 "$PKGROOT/usr/bin/aims"

  cp "$ROOT/packaging/debian/aims.desktop" \
    "$PKGROOT/usr/share/applications/${PKG_ID}.desktop"

  LOGO="$ROOT/assets/branding/logo.png"
  if [[ -f "$LOGO" ]]; then
    cp "$LOGO" "$PKGROOT/usr/share/icons/hicolor/256x256/apps/aims.png"
    cp "$LOGO" "$PKGROOT/usr/share/icons/hicolor/128x128/apps/aims.png"
  fi

  INSTALLED_KB="$(du -sk "$PKGROOT" | awk '{print $1}')"
  cat > "$PKGROOT/DEBIAN/control" <<EOF
Package: aims
Version: ${VERSION}
Section: office
Priority: optional
Architecture: ${DEB_ARCH}
Maintainer: iGenHR <support@igenhr.com>
Depends: libc6 (>= 2.31), libgtk-3-0t64 (>= 3.24) | libgtk-3-0 (>= 3.24), libblkid1, liblzma5, libsecret-1-0, libgstreamer1.0-0 (>= 1.16), libgstreamer-plugins-base1.0-0 (>= 1.16), libjsoncpp26 | libjsoncpp25 | libjsoncpp24 | libjsoncpp1
Recommends: gstreamer1.0-plugins-base, gstreamer1.0-plugins-good, gnome-screenshot | grim | scrot
Installed-Size: ${INSTALLED_KB}
Homepage: https://igenhr.com
Description: AIMS — iGenHR client
 Desktop client for the iGenHR / AIMS workforce platform.
 Supports attendance, tasks, chat, and team workflows on Linux.
EOF

  cp "$ROOT/packaging/debian/postinst" "$PKGROOT/DEBIAN/postinst"
  cp "$ROOT/packaging/debian/prerm" "$PKGROOT/DEBIAN/prerm"
  chmod 755 "$PKGROOT/DEBIAN/postinst" "$PKGROOT/DEBIAN/prerm"

  rm -f "$DEB_FILE"
  dpkg-deb --root-owner-group --build "$PKGROOT" "$DEB_FILE"
  echo "    Package: $DEB_FILE"
fi

echo ""
echo "Done."
if [[ "$BUILD_TAR" == true ]]; then
  echo "  Portable : dist/${OUT_NAME}.tar.gz"
fi
if [[ "$BUILD_DEB" == true ]]; then
  echo "  Debian   : dist/aims_${VERSION}_${DEB_ARCH}.deb"
  echo ""
  echo "Install on Ubuntu/Debian:"
  echo "  sudo apt install ./dist/aims_${VERSION}_${DEB_ARCH}.deb"
fi
if [[ "$BUILD_TAR" == true ]]; then
  echo ""
  echo "Or portable:"
  echo "  tar -xzf dist/${OUT_NAME}.tar.gz && cd ${OUT_NAME} && ./run-aims.sh"
fi
