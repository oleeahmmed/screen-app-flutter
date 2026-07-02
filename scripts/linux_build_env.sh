#!/usr/bin/env bash
# Source before building on this machine when apt/sudo is unavailable:
#   source scripts/linux_build_env.sh
#   bash scripts/build_linux_release.sh --skip-apt

SYSROOT="${LINUX_BUILD_SYSROOT:-$HOME/.local/linux-build/sysroot}"

if [[ ! -d "$SYSROOT/usr/include/gtk-3.0" ]]; then
  echo "Linux build sysroot not found at $SYSROOT"
  echo "Run: bash scripts/setup_linux_build_env.sh"
  return 1 2>/dev/null || exit 1
fi

export PATH="$HOME/flutter/bin:$HOME/.local/bin:$SYSROOT/usr/bin:${PATH}"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/x86_64-linux-gnu/pkgconfig:$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export LIBRARY_PATH="$SYSROOT/usr/lib/x86_64-linux-gnu:$SYSROOT/usr/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"
export LD_LIBRARY_PATH="$SYSROOT/usr/lib/x86_64-linux-gnu:$SYSROOT/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export CPLUS_INCLUDE_PATH="$SYSROOT/usr/include${CPLUS_INCLUDE_PATH:+:$CPLUS_INCLUDE_PATH}"
export C_INCLUDE_PATH="$SYSROOT/usr/include${C_INCLUDE_PATH:+:$C_INCLUDE_PATH}"

mkdir -p "$HOME/.local/bin"
ln -sf "$SYSROOT/usr/bin/clang" "$HOME/.local/bin/clang"
ln -sf "$SYSROOT/usr/bin/clang++" "$HOME/.local/bin/clang++"
ln -sf "$SYSROOT/usr/bin/cmake" "$HOME/.local/bin/cmake"
ln -sf "$SYSROOT/usr/bin/ninja" "$HOME/.local/bin/ninja"
ln -sf "$SYSROOT/usr/bin/pkg-config" "$HOME/.local/bin/pkg-config"
