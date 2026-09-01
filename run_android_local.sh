#!/usr/bin/env bash
# Run Flutter against the local Daphne backend.
# Prefers an authorized Android device. Does not fall back to Linux
# (Linux needs system cmake + GTK headers this machine does not have).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
LAN_IP="${LAN_IP:-192.168.1.112}"
ORIGIN="http://${LAN_IP}:8000"

# Gradle + Android SDK live on NTFS "New Volume" via symlinks.
udisksctl mount -b /dev/nvme0n1p4 >/dev/null 2>&1 || true

export JAVA_HOME="${JAVA_HOME:-$HOME/.local/java/jdk-17}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export PATH="$HOME/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.gradle}"

adb_state="$(adb devices 2>/dev/null | awk 'NR>1 && $1 != "" {print $1, $2}')"

if echo "$adb_state" | grep -qE 'emulator-[0-9]+ device'; then
  if ! echo "$adb_state" | grep -v emulator | grep -qE ' device$'; then
    ORIGIN="http://10.0.2.2:8000"
  fi
fi

android_id="$(echo "$adb_state" | awk '$2=="device" {print $1; exit}')"

echo "API_ORIGIN=$ORIGIN"

if [[ -z "$android_id" ]]; then
  echo
  echo "No authorized Android device. flutter run defaulted to Linux last time;"
  echo "Linux desktop needs: sudo apt install cmake ninja-build pkg-config libgtk-3-dev clang"
  echo
  if echo "$adb_state" | grep -q 'no permissions\|unauthorized\|offline'; then
    echo "Phone is plugged in but adb cannot access USB. Unlock the phone, accept"
    echo "the USB debugging prompt, then run:"
    echo "  sudo chmod a+rw /dev/bus/usb/001/009"
    echo "  adb devices"
    echo "  $0"
  else
    echo "Plug in the phone with USB debugging on, or pass a device:"
    echo "  flutter run -d chrome --dart-define=API_ORIGIN=$ORIGIN"
  fi
  exit 1
fi

cd "$ROOT"
exec flutter run -d "$android_id" --dart-define="API_ORIGIN=$ORIGIN" --android-skip-build-dependency-validation "$@"
