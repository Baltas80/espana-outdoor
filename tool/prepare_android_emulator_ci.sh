#!/usr/bin/env bash
# Stabilize Google APIs emulator first-boot setup before UI/integration tests.
# This is deliberately opt-in: never disable packages on a physical user device.
set -euo pipefail

if [[ "${ANDROID_EMULATOR_CI:-false}" != "true" ]]; then
  exit 0
fi

DEVICE_SERIAL="${ANDROID_SERIAL:-emulator-5554}"
adb -s "${DEVICE_SERIAL}" get-state | grep -qx device

setup_package="com.google.android.googlesdksetup"
if adb -s "${DEVICE_SERIAL}" shell pm path "${setup_package}" >/dev/null 2>&1; then
  adb -s "${DEVICE_SERIAL}" shell am force-stop "${setup_package}" >/dev/null 2>&1 || true
  adb -s "${DEVICE_SERIAL}" shell pm disable-user --user 0 "${setup_package}" >/dev/null
  if ! adb -s "${DEVICE_SERIAL}" shell pm list packages -d | tr -d '\r' | grep -Fxq "package:${setup_package}"; then
    echo "ERROR: Google SDK setup did not enter disabled-user state."
    exit 1
  fi
  echo "ANDROID_EMULATOR_SYSTEM package=${setup_package} state=disabled-user"
fi

sleep 2
anr_windows="$(adb -s "${DEVICE_SERIAL}" shell dumpsys window windows | grep -F 'Application Not Responding' || true)"
if [[ -n "${anr_windows}" ]]; then
  echo "ERROR: Android system ANR overlay remains after emulator setup stabilization."
  printf '%s\n' "${anr_windows}"
  exit 1
fi

echo "ANDROID_EMULATOR_SYSTEM anr_overlay=absent"
