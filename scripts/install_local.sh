#!/usr/bin/env bash
# Install AIMS for current user — no sudo required.
#
# Usage:
#   bash scripts/install_local.sh
#   bash scripts/install_local.sh dist/aims_1.0.0_amd64.deb
#   bash scripts/install_local.sh dist/aims-linux-amd64-1.0.0.tar.gz

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="${AIMS_INSTALL_DIR:-$HOME/.local/opt/aims}"
BIN_DIR="${AIMS_BIN_DIR:-$HOME/.local/bin}"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"

INPUT="${1:-$ROOT/dist/aims-linux-amd64-1.0.0.tar.gz}"
if [[ ! -f "$INPUT" && -f "$ROOT/dist/aims_1.0.0_amd64.deb" ]]; then
  INPUT="$ROOT/dist/aims_1.0.0_amd64.deb"
fi

if [[ ! -f "$INPUT" ]]; then
  echo "ERROR: Package not found."
  echo "Build first:  bash scripts/build_linux_release.sh"
  echo "Or pass path: bash scripts/install_local.sh dist/aims_1.0.0_amd64.deb"
  exit 1
fi

echo "==> Installing AIMS to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$DESKTOP_DIR" "$ICON_DIR"

case "$INPUT" in
  *.deb)
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    dpkg-deb -x "$INPUT" "$TMP"
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    cp -a "$TMP/opt/aims/." "$INSTALL_DIR/"
    if [[ -f "$TMP/usr/share/applications/"*.desktop ]]; then
      cp "$TMP/usr/share/applications/"*.desktop "$DESKTOP_DIR/"
    fi
    if [[ -f "$TMP/usr/share/icons/hicolor/256x256/apps/aims.png" ]]; then
      cp "$TMP/usr/share/icons/hicolor/256x256/apps/aims.png" "$ICON_DIR/aims.png"
    fi
    ;;
  *.tar.gz)
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    tar -xzf "$INPUT" -C "$TMP"
    BUNDLE="$(find "$TMP" -maxdepth 1 -type d -name 'aims-linux-*' | head -1)"
    if [[ -z "$BUNDLE" ]]; then
      echo "ERROR: Invalid tar.gz layout"
      exit 1
    fi
    rm -rf "$INSTALL_DIR"
    cp -a "$BUNDLE" "$INSTALL_DIR"
    if [[ -f "$INSTALL_DIR/assets/branding/logo.png" ]]; then
      :
    elif [[ -f "$INSTALL_DIR/data/flutter_assets/assets/branding/logo.png" ]]; then
      cp "$INSTALL_DIR/data/flutter_assets/assets/branding/logo.png" "$ICON_DIR/aims.png" 2>/dev/null || true
    fi
    cat > "$DESKTOP_DIR/com.igenhr.aims.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=AIMS
Comment=iGenHR client
Exec=$BIN_DIR/aims
Icon=$ICON_DIR/aims.png
Terminal=false
Categories=Office;
StartupWMClass=aims
EOF
    ;;
  *)
    echo "ERROR: Unsupported file: $INPUT (use .deb or .tar.gz)"
    exit 1
    ;;
esac

cat > "$BIN_DIR/aims" <<EOF
#!/bin/sh
exec "$INSTALL_DIR/aims" "\$@"
EOF
chmod +x "$BIN_DIR/aims" "$INSTALL_DIR/aims"

if [[ -f "$ROOT/assets/branding/logo.png" && ! -f "$ICON_DIR/aims.png" ]]; then
  cp "$ROOT/assets/branding/logo.png" "$ICON_DIR/aims.png"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q "$DESKTOP_DIR" 2>/dev/null || true
fi

echo ""
echo "Done."
echo "  App files : $INSTALL_DIR"
echo "  Launcher  : $BIN_DIR/aims"
echo ""
echo "Add to PATH (if needed), then run:"
echo "  export PATH=\"$BIN_DIR:\$PATH\""
echo "  aims"
echo ""
echo "Or log out/in — app menu may show AIMS."
