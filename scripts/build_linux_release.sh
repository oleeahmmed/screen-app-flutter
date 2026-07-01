#!/usr/bin/env bash
# Build AIMS for Ubuntu/Linux and create a portable .tar.gz for other users.
#
# Run on Ubuntu 22.04+ (or similar):
#   bash scripts/build_linux_release.sh
#
# Output:
#   dist/aims-linux-x64-<version>.tar.gz
#   dist/aims-linux-x64-<version>/   (extracted bundle)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
ARCH="$(uname -m)"
OUT_NAME="aims-linux-${ARCH}-${VERSION}"
DIST="$ROOT/dist"
BUNDLE="$ROOT/build/linux/x64/release/bundle"

echo "==> AIMS Linux release build (v${VERSION}, ${ARCH})"

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: Flutter not found. Install Flutter first:"
  echo "  https://docs.flutter.dev/get-started/install/linux"
  exit 1
fi

echo "==> Checking Flutter Linux support..."
flutter config --enable-linux-desktop >/dev/null 2>&1 || true
flutter doctor -v

echo "==> Installing build dependencies (Ubuntu/Debian)..."
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y \
    clang cmake ninja-build pkg-config \
    libgtk-3-dev libblkid-dev liblzma-dev \
    libsecret-1-dev libjsoncpp-dev \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
fi

echo "==> flutter pub get"
flutter pub get

echo "==> flutter build linux --release"
flutter build linux --release

if [[ ! -d "$BUNDLE" ]]; then
  echo "ERROR: Expected bundle at $BUNDLE"
  exit 1
fi

mkdir -p "$DIST"
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
Copy aims.desktop to ~/.local/share/applications/ then edit paths inside.

Screenshot capture (optional, for clock-in monitoring)
--------------------------------------------------------
Install one of:
  sudo apt install gnome-screenshot
  sudo apt install grim        # Wayland
  sudo apt install scrot maim  # alternatives

System libraries (usually already on Ubuntu Desktop)
----------------------------------------------------
  sudo apt install libgtk-3-0 libsecret-1-0 libgstreamer1.0-0
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

echo ""
echo "Done."
echo "  Folder : $STAGE"
echo "  Archive: $ARCHIVE"
echo ""
echo "Send the .tar.gz to another Ubuntu user. They run:"
echo "  tar -xzf ${OUT_NAME}.tar.gz"
echo "  cd ${OUT_NAME}"
echo "  ./run-aims.sh"
