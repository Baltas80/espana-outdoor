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
if [[ -z "${anr_windows}" ]]; then
  echo "ANDROID_EMULATOR_SYSTEM anr_overlay=absent"
elif grep -qi 'com.google.android.apps.nexuslauncher' <<<"${anr_windows}" && ! grep -viq 'com.google.android.apps.nexuslauncher' <<<"${anr_windows}"; then
  # The map smoke owns the UI-level ANR classifier and closes only this unrelated launcher dialog.
  echo "ANDROID_EMULATOR_SYSTEM anr_overlay=launcher_deferred_to_smoke_guard"
  printf '%s\n' "${anr_windows}"
else
  echo "ERROR: unexpected Android system ANR overlay; refusing to hide it."
  printf '%s\n' "${anr_windows}"
  exit 1
fi
