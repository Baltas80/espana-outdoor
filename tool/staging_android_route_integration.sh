#!/usr/bin/env bash
set -Eeuo pipefail

DEVICE_SERIAL="${ANDROID_SERIAL:-emulator-5554}"
PACKAGE_NAME="${ANDROID_APPLICATION_ID:-com.espanaoutdoors.espana_outdoors}"
# Flutter's integration-test runner is installed under the Android Gradle
# namespace, which is intentionally different from the staging application ID.
TEST_PACKAGE_NAME="$(sed -nE 's/^[[:space:]]*namespace[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' android/app/build.gradle.kts | head -n 1)"
EVIDENCE_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
LOGCAT_PATH="$EVIDENCE_DIR/espana-outdoor-route-logcat.txt"
TEST_LOG_PATH="$EVIDENCE_DIR/espana-outdoor-route-test-output.txt"
AIRPLANE_CHANGED=0
ORIGINAL_AIRPLANE=""
ORIGINAL_WIFI=""

if [[ -z "$TEST_PACKAGE_NAME" ]]; then
  echo "ERROR: could not resolve Android integration-test package from Gradle namespace."
  exit 1
fi

restore_network() {
  local status=$?
  trap - EXIT HUP INT TERM
  if [[ "$AIRPLANE_CHANGED" == "1" ]]; then
    local restore_action=disable
    local restore_state=false
    if [[ "$ORIGINAL_AIRPLANE" == "1" ]]; then
      restore_action=enable
      restore_state=true
    fi
    adb -s "$DEVICE_SERIAL" shell cmd connectivity airplane-mode "$restore_action" >/dev/null 2>&1 || {
      adb -s "$DEVICE_SERIAL" shell settings put global airplane_mode_on "$ORIGINAL_AIRPLANE" >/dev/null 2>&1 || true
      adb -s "$DEVICE_SERIAL" shell am broadcast -a android.intent.action.AIRPLANE_MODE \
        --ez state "$restore_state" >/dev/null 2>&1 || true
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
test -n "${MAPBOX_DOWNLOADS_TOKEN:-}"
[[ "$MAPBOX_ACCESS_TOKEN" == pk.* ]]
adb -s "$DEVICE_SERIAL" get-state | grep -qx device

ORIGINAL_AIRPLANE="$(adb -s "$DEVICE_SERIAL" shell settings get global airplane_mode_on | tr -d '\r\n')"
ORIGINAL_WIFI="$(adb -s "$DEVICE_SERIAL" shell settings get global wifi_on | tr -d '\r\n')"
[[ "$ORIGINAL_AIRPLANE" == 0 || "$ORIGINAL_AIRPLANE" == 1 ]]
[[ "$ORIGINAL_WIFI" == 0 || "$ORIGINAL_WIFI" == 1 ]]

run_route_phase() {
  local mode="$1"
  echo "ROUTE_PHASE_START mode=$mode test_package=$TEST_PACKAGE_NAME app_package=$PACKAGE_NAME"
  # Dependencies were already resolved with --enforce-lockfile by the workflow.
  # Avoid an implicit pub get between online and offline phases.
  timeout --signal=TERM --kill-after=15s 8m flutter test --no-pub \
    --reporter expanded \
    -d "$DEVICE_SERIAL" \
    --dart-define=MAPBOX_ACCESS_TOKEN="$MAPBOX_ACCESS_TOKEN" \
    --dart-define=ROUTE_TEST_MODE="$mode" \
    integration_test/mapbox_android_live_route_test.dart 2>&1 | tee -a "$TEST_LOG_PATH"
  echo "ROUTE_PHASE_PROCESS_EXIT mode=$mode"
}

stop_integration_app() {
  echo "Stopping integration-test and staging packages before offline relaunch."
  adb -s "$DEVICE_SERIAL" shell am force-stop "$TEST_PACKAGE_NAME"
  adb -s "$DEVICE_SERIAL" shell am force-stop "$PACKAGE_NAME"
  sleep 2
  if adb -s "$DEVICE_SERIAL" shell pidof "$TEST_PACKAGE_NAME" >/dev/null 2>&1; then
    echo "ERROR: integration-test process $TEST_PACKAGE_NAME survived force-stop."
    return 1
  fi
  if adb -s "$DEVICE_SERIAL" shell pidof "$PACKAGE_NAME" >/dev/null 2>&1; then
    echo "ERROR: staging process $PACKAGE_NAME survived force-stop."
    return 1
  fi
}

run_route_phase online_and_download

AIRPLANE_CHANGED=1
adb -s "$DEVICE_SERIAL" shell cmd connectivity airplane-mode enable || {
  adb -s "$DEVICE_SERIAL" shell settings put global airplane_mode_on 1
  adb -s "$DEVICE_SERIAL" shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true >/dev/null
}
adb -s "$DEVICE_SERIAL" shell svc wifi disable
sleep 3
[[ "$(adb -s "$DEVICE_SERIAL" shell settings get global airplane_mode_on | tr -d '\r\n')" == 1 ]]
[[ "$(adb -s "$DEVICE_SERIAL" shell settings get global wifi_on | tr -d '\r\n')" == 0 ]]
stop_integration_app
run_route_phase offline

adb -s "$DEVICE_SERIAL" shell settings get global airplane_mode_on | tr -d '\r\n' | grep -qx 1
adb -s "$DEVICE_SERIAL" shell settings get global wifi_on | tr -d '\r\n' | grep -qx 0
adb -s "$DEVICE_SERIAL" logcat -d > "$LOGCAT_PATH"
grep -q 'MAPBOX_ROUTE_VALIDATION source=online' "$TEST_LOG_PATH"
grep -q 'MAPBOX_ROUTE_VALIDATION source=offline' "$TEST_LOG_PATH"
grep -q 'MAPBOX_OFFLINE_MAP_RENDERED' "$TEST_LOG_PATH"
