#!/usr/bin/env bash
set -Eeuo pipefail

DEVICE_SERIAL="${ANDROID_SERIAL:-emulator-5554}"
MAPBOX_OFFLINE_EXPERIMENT_STYLE_URI="${MAPBOX_OFFLINE_EXPERIMENT_STYLE_URI:-mapbox://styles/mapbox/standard}"
PACKAGE_NAME="${ANDROID_APPLICATION_ID:-com.espanaoutdoors.espana_outdoors}"
# Flutter's integration-test runner is installed under the Android Gradle
# namespace, which is intentionally different from the staging application ID.
TEST_PACKAGE_NAME="$(sed -nE 's/^[[:space:]]*namespace[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' android/app/build.gradle.kts | head -n 1)"
EVIDENCE_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"

if [[ "${ANDROID_EMULATOR_CI:-false}" == "true" ]]; then
  bash "$(dirname "${BASH_SOURCE[0]}")/prepare_android_emulator_ci.sh"
fi
LOGCAT_PATH="$EVIDENCE_DIR/espana-outdoor-route-logcat.txt"
TEST_LOG_PATH="$EVIDENCE_DIR/espana-outdoor-route-test-output.txt"
SCREENSHOT_PATH="$EVIDENCE_DIR/espana-outdoor-offline-map.png"
AIRPLANE_CHANGED=0
ORIGINAL_AIRPLANE=""
ORIGINAL_WIFI=""

if [[ -z "$TEST_PACKAGE_NAME" ]]; then
  echo "ERROR: could not resolve Android integration-test package from Gradle namespace."
  exit 1
fi

capture_route_logcat() {
  # Preserve native Mapbox failures even when the offline assertion exits early.
  # Capture before restoring radios so IN_OFFLINE_MODE diagnostics remain intact.
  if adb -s "$DEVICE_SERIAL" get-state 2>/dev/null | grep -qx device; then
    adb -s "$DEVICE_SERIAL" logcat -d 2>/dev/null |
      sed -E 's/(^|[^[:alnum:]])(pk|sk)\.[A-Za-z0-9._~-]{10,}/\1\2.<REDACTED>/g' > "$LOGCAT_PATH" || true
  fi
}

restore_network() {
  local status=$?
  trap - EXIT HUP INT TERM
  capture_route_logcat
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

# The online/download phase must start with a genuinely connected emulator.
# Capture the original radio state first so the EXIT trap can restore it.
bash "$(dirname "${BASH_SOURCE[0]}")/ensure_android_emulator_online.sh"

run_route_phase() {
  local mode="$1"
  local phase_status=0
  local tile_store_usage_mode=READ_ONLY
  if [[ "$mode" == "offline" ]]; then tile_store_usage_mode=READ_AND_UPDATE; fi
  echo "ROUTE_PHASE_START mode=$mode test_package=$TEST_PACKAGE_NAME app_package=$PACKAGE_NAME"
  echo "MAPBOX_OFFLINE_STYLE_EXPERIMENT uri=$MAPBOX_OFFLINE_EXPERIMENT_STYLE_URI production_default=mapbox://styles/mapbox/outdoors-v12"
  if [[ "$mode" == "offline" ]]; then
    # Flutter integration_test output can be buffered by the host test runner.
    # Use Android logcat as the screenshot-ready signal, not the host stdout pipe.
    adb -s "$DEVICE_SERIAL" logcat -c
  fi
  # Dependencies were already resolved with --enforce-lockfile by the workflow.
  # Avoid an implicit pub get between online and offline phases.
  timeout --signal=TERM --kill-after=15s 8m flutter test --no-pub \
    --reporter expanded \
    -d "$DEVICE_SERIAL" \
    --dart-define=MAPBOX_ACCESS_TOKEN="$MAPBOX_ACCESS_TOKEN" \
    --dart-define=ROUTE_TEST_MODE="$mode" \
    --dart-define=MAPBOX_TILESTORE_USAGE_MODE="$tile_store_usage_mode" \
    --dart-define=MAPBOX_STYLE_URI="$MAPBOX_OFFLINE_EXPERIMENT_STYLE_URI" \
    integration_test/mapbox_android_live_route_test.dart 2>&1 | sed -u -E 's/(^|[^[:alnum:]])(pk|sk)\.[A-Za-z0-9._~-]{10,}/\1\2.<REDACTED>/g' | tee -a "$TEST_LOG_PATH" &
  local phase_pid=$!

  local screenshot_captured=0
  local foreground_package=""
  if [[ "$mode" == "offline" ]]; then
    rm -f "$SCREENSHOT_PATH"
    # The screenshot is useful only while the app under test is the resumed
    # activity. A launcher/wallpaper PNG can have high entropy and must never
    # be accepted as Mapbox evidence.
    for attempt in $(seq 1 360); do
      offline_logcat="$(adb -s "$DEVICE_SERIAL" logcat -d -s EspanaOfflineTest:I 2>/dev/null || true)"
      if grep -Fq 'MAPBOX_OFFLINE_SCREENSHOT_READY' <<<"$offline_logcat"; then
        foreground_activity="$(adb -s "$DEVICE_SERIAL" shell dumpsys activity activities 2>/dev/null | tr -d '\r' | grep -E 'mResumedActivity|topResumedActivity' | tail -n 1 || true)"
        if [[ -z "$foreground_activity" ]]; then
          foreground_activity="$(adb -s "$DEVICE_SERIAL" shell dumpsys window windows 2>/dev/null | tr -d '\r' | grep -E 'mCurrentFocus|mFocusedApp' | tail -n 1 || true)"
        fi
        # dumpsys prefixes the component with applicationId, while the
        # Activity class belongs to Gradle namespace. They are intentionally
        # different in this staging build.
        foreground_component="$(printf '%s\n' "$foreground_activity" | sed -nE 's/.*ActivityRecord\{[^}]*[[:space:]]u[0-9]+[[:space:]]([^[:space:]]+).*/\1/p' | tail -n 1)"
        if [[ -z "$foreground_component" ]]; then
          foreground_component="$(printf '%s\n' "$foreground_activity" | sed -nE 's/.*Window\{[^}]*[[:space:]]u[0-9]+[[:space:]]([^[:space:]]+).*/\1/p' | tail -n 1)"
        fi
        expected_component="$PACKAGE_NAME/$TEST_PACKAGE_NAME.MainActivity"
        case "$foreground_component" in
          "$expected_component") foreground_package="$PACKAGE_NAME" ;;
          *)
            echo "MAPBOX_OFFLINE_SCREENSHOT_WAITING_FOR_TEST_APP attempt=$attempt expected=$expected_component observed=$foreground_component" | tee -a "$TEST_LOG_PATH"
            ;;
        esac
        if [[ -n "$foreground_package" ]]; then
          echo "MAPBOX_OFFLINE_SCREENSHOT_FOREGROUND package=$foreground_package verified=true" | tee -a "$TEST_LOG_PATH"
          if adb -s "$DEVICE_SERIAL" exec-out screencap -p > "$SCREENSHOT_PATH" && test -s "$SCREENSHOT_PATH"; then
            echo "MAPBOX_OFFLINE_SCREENSHOT_CAPTURED bytes=$(wc -c < "$SCREENSHOT_PATH" | tr -d ' ')" | tee -a "$TEST_LOG_PATH"
            screenshot_captured=1
          else
            echo "MAPBOX_OFFLINE_SCREENSHOT_ERROR capture_failed=true" | tee -a "$TEST_LOG_PATH"
            phase_status=1
          fi
          break
        fi
      fi
      if ! kill -0 "$phase_pid" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    if [[ "$screenshot_captured" != "1" ]]; then
      echo "MAPBOX_OFFLINE_SCREENSHOT_ERROR foreground_verified=false captured=false" | tee -a "$TEST_LOG_PATH"
      phase_status=1
    fi
  fi

  if wait "$phase_pid"; then
    :
  else
    phase_status=$?
  fi

  if [[ "$mode" == "offline" ]]; then
    if [[ "$screenshot_captured" == "1" && -s "$SCREENSHOT_PATH" && -n "$foreground_package" ]]; then
      if python3 tool/verify_android_map_screenshot.py --foreground-package "$foreground_package" "$SCREENSHOT_PATH" 2>&1 | tee -a "$TEST_LOG_PATH"; then
        :
      else
        phase_status=1
      fi
    else
      echo "MAPBOX_OFFLINE_SCREENSHOT_ERROR rejected_without_verified_foreground=true" | tee -a "$TEST_LOG_PATH"
      phase_status=1
    fi
  fi

  echo "ROUTE_PHASE_PROCESS_EXIT mode=$mode status=$phase_status"
  return "$phase_status"
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
adb -s "$DEVICE_SERIAL" logcat -d | sed -E 's/(^|[^[:alnum:]])(pk|sk)\.[A-Za-z0-9._~-]{10,}/\1\2.<REDACTED>/g' > "$LOGCAT_PATH"
grep -q 'MAPBOX_ROUTE_VALIDATION source=online' "$TEST_LOG_PATH"
grep -q 'MAPBOX_ROUTE_VALIDATION source=offline' "$TEST_LOG_PATH"
grep -q 'MAPBOX_OFFLINE_SCREENSHOT_FOREGROUND .* verified=true' "$TEST_LOG_PATH"
grep -q 'MAPBOX_OFFLINE_MAP_RENDERED' "$TEST_LOG_PATH"
grep -Eq 'MAPBOX_OFFLINE_MAP_DIAGNOSTICS style_loaded=true map_loaded=true full_frame=true rendered_frames=[1-9][0-9]* idle=true load_errors=0 resource_failures=0' "$TEST_LOG_PATH"
