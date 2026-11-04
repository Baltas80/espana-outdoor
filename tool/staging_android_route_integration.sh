#!/usr/bin/env bash
set -Eeuo pipefail

DEVICE_SERIAL="${ANDROID_SERIAL:-emulator-5554}"
PACKAGE_NAME="com.espanaoutdoors.espana_outdoors"
EVIDENCE_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
LOGCAT_PATH="$EVIDENCE_DIR/espana-outdoor-route-logcat.txt"
TEST_LOG_PATH="$EVIDENCE_DIR/espana-outdoor-route-test-output.txt"
AIRPLANE_CHANGED=0
ORIGINAL_AIRPLANE=""
ORIGINAL_WIFI=""

restore_network() {
  local status=$?
  trap - EXIT HUP INT TERM
  if [[ "$AIRPLANE_CHANGED" == "1" ]]; then
    adb -s "$DEVICE_SERIAL" shell cmd connectivity airplane-mode disable >/dev/null 2>&1 || {
      adb -s "$DEVICE_SERIAL" shell settings put global airplane_mode_on "$ORIGINAL_AIRPLANE" >/dev/null 2>&1 || true
      adb -s "$DEVICE_SERIAL" shell am broadcast -a android.intent.action.AIRPLANE_MODE \
        --ez state "$([[ "$ORIGINAL_AIRPLANE" == "1" ]] && echo true || echo false)" >/dev/null 2>&1 || true
    }
  fi
  if [[ "$ORIGINAL_WIFI" == "1" ]]; then
    adb -s "$DEVICE_SERIAL" shell svc wifi enable >/dev/null 2>&1 || true
  elif [[ "$ORIGINAL_WIFI" == "0" ]]; then
    adb -s "$DEVICE_SERIAL" shell svc wifi disable >/dev/null 2>&1 || true
  fi
  exit "$status"
}

trap restore_network EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

test -n "${MAPBOX_ACCESS_TOKEN:-}"
[[ "$MAPBOX_ACCESS_TOKEN" == pk.* ]]
adb -s "$DEVICE_SERIAL" get-state | grep -qx device

ORIGINAL_AIRPLANE="$(adb -s "$DEVICE_SERIAL" shell settings get global airplane_mode_on | tr -d '\r\n')"
ORIGINAL_WIFI="$(adb -s "$DEVICE_SERIAL" shell settings get global wifi_on | tr -d '\r\n')"
[[ "$ORIGINAL_AIRPLANE" == 0 || "$ORIGINAL_AIRPLANE" == 1 ]]
[[ "$ORIGINAL_WIFI" == 0 || "$ORIGINAL_WIFI" == 1 ]]

flutter test -d "$DEVICE_SERIAL" \
  --dart-define=MAPBOX_ACCESS_TOKEN="$MAPBOX_ACCESS_TOKEN" \
  --dart-define=ROUTE_TEST_MODE=online_and_download \
  integration_test/mapbox_android_live_route_test.dart 2>&1 | tee "$TEST_LOG_PATH"

adb -s "$DEVICE_SERIAL" shell cmd connectivity airplane-mode enable || {
  adb -s "$DEVICE_SERIAL" shell settings put global airplane_mode_on 1
  adb -s "$DEVICE_SERIAL" shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true >/dev/null
}
AIRPLANE_CHANGED=1
adb -s "$DEVICE_SERIAL" shell svc wifi disable
sleep 3
[[ "$(adb -s "$DEVICE_SERIAL" shell settings get global airplane_mode_on | tr -d '\r\n')" == 1 ]]
[[ "$(adb -s "$DEVICE_SERIAL" shell settings get global wifi_on | tr -d '\r\n')" == 0 ]]
adb -s "$DEVICE_SERIAL" shell am force-stop "$PACKAGE_NAME"

flutter test -d "$DEVICE_SERIAL" \
  --dart-define=MAPBOX_ACCESS_TOKEN="$MAPBOX_ACCESS_TOKEN" \
  --dart-define=ROUTE_TEST_MODE=offline \
  integration_test/mapbox_android_live_route_test.dart 2>&1 | tee -a "$TEST_LOG_PATH"

adb -s "$DEVICE_SERIAL" shell settings get global airplane_mode_on | tr -d '\r\n' | grep -qx 1
adb -s "$DEVICE_SERIAL" shell settings get global wifi_on | tr -d '\r\n' | grep -qx 0
adb -s "$DEVICE_SERIAL" logcat -d > "$LOGCAT_PATH"
grep -q 'MAPBOX_ROUTE_VALIDATION source=online' "$TEST_LOG_PATH"
grep -q 'MAPBOX_ROUTE_VALIDATION source=offline' "$TEST_LOG_PATH"
