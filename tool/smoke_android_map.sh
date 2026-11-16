#!/usr/bin/env bash
set -euo pipefail

apk_path="${1:?APK path required}"
offline_mode="${2:-online}"
ADB_COMMAND="${ADB:-adb}"
if ! command -v "${ADB_COMMAND}" >/dev/null 2>&1; then
  echo "ERROR: adb executable was not found." >&2
  exit 2
fi
if ! command -v timeout >/dev/null 2>&1; then
  echo "ERROR: GNU timeout is required to bound Android emulator commands." >&2
  exit 2
fi

# Bound every adb call. UIAutomator/dumpsys can otherwise hang indefinitely
# when the emulator loses its system-server or instrumentation connection.
adb() {
  local limit=20
  case "${1:-}" in
    wait-for-device) limit=120 ;;
    install) limit=180 ;;
    logcat) limit=60 ;;
    exec-out) limit=30 ;;
    shell)
      case "${2:-}" in
        uiautomator) limit=45 ;;
        dumpsys) limit=20 ;;
        monkey) limit=30 ;;
        *) limit=15 ;;
      esac
      ;;
  esac
  timeout --foreground --signal=TERM --kill-after=5s "${limit}s" "${ADB_COMMAND}" "$@"
}
aapt_path="$(find "${ANDROID_HOME}/build-tools" -maxdepth 2 -type f -name aapt -print | sort -V | tail -n 1)"
test -x "${aapt_path}"
package_name="$("${aapt_path}" dump badging "${apk_path}" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -n 1)"
test -n "${package_name}"

echo "Installing ${package_name}"
adb wait-for-device

# The Google APIs API-35 image repeatedly presents a system ANR for its
# first-run SDK setup activity. It is unrelated to the app and blocks all UI
# input while leaving the app task "resumed". Disable only this provisioning
# package on the disposable CI emulator; never run this on a physical device.
stabilize_emulator_setup_packages() {
  local setup_package="com.google.android.googlesdksetup"
  local package_paths disable_output disabled_packages
  package_paths="$(adb shell pm path "${setup_package}" 2>/dev/null | tr -d '\r' || true)"
  if [[ -z "${package_paths}" ]]; then
    echo "ANDROID_EMULATOR_SYSTEM_PACKAGE package=${setup_package} installed=false"
    return 0
  fi

  adb shell am force-stop "${setup_package}" >/dev/null 2>&1 || true
  disable_output="$(adb shell pm disable-user --user 0 "${setup_package}" 2>&1 | tr -d '\r' || true)"
  disabled_packages="$(adb shell pm list packages -d 2>/dev/null | tr -d '\r' || true)"
  if ! grep -Fxq "package:${setup_package}" <<<"${disabled_packages}"; then
    echo "ERROR: failed to disable the known first-run emulator setup package." >&2
    printf '%s\n' "${disable_output}" >&2
    exit 1
  fi
  adb shell am force-stop "${setup_package}" >/dev/null 2>&1 || true
  echo "ANDROID_EMULATOR_SYSTEM_PACKAGE package=${setup_package} disabled=true"
}

stabilize_emulator_setup_packages
adb install -r "${apk_path}"

ui_dump() {
  local file="$1"
  local remote_file="/sdcard/espana-outdoor-uiautomator.xml"
  # UIAutomator expects a regular device-side output file. Writing to /dev/tty
  # is unreliable on non-interactive adb exec-out sessions (no controlling TTY).
  if ! adb shell uiautomator dump "$remote_file" >/dev/null 2>&1; then
    echo "ERROR: UIAutomator dump failed or timed out (45s)." >&2
    return 1
  fi
  if ! adb shell cat "$remote_file" >"${file}"; then
    echo "ERROR: unable to retrieve the UIAutomator hierarchy from the device." >&2
    return 1
  fi
  if ! grep -q '<hierarchy' "${file}"; then
    echo "ERROR: UIAutomator returned no hierarchy XML." >&2
    return 1
  fi
}

window_file="${RUNNER_TEMP:-/tmp}/espana-window.xml"
post_window="${RUNNER_TEMP:-/tmp}/espana-window-post-map.xml"
logcat_file="${RUNNER_TEMP:-/tmp}/espana-outdoor-map-logcat.txt"
screenshot_file="${RUNNER_TEMP:-/tmp}/espana-outdoor-map.png"
capture_failure_evidence() {
  local exit_code=$?
  trap - EXIT
  if [[ ! -s "${logcat_file}" ]]; then
    adb logcat -d >"${logcat_file}" 2>/dev/null || true
  fi
  if [[ ! -s "${window_file}" ]]; then
    ui_dump "${window_file}" >/dev/null 2>&1 || true
  fi
  if [[ ! -s "${post_window}" ]]; then
    ui_dump "${post_window}" >/dev/null 2>&1 || true
  fi
  if [[ ! -s "${screenshot_file}" ]]; then
    adb exec-out screencap -p >"${screenshot_file}" 2>/dev/null || true
  fi
  exit "${exit_code}"
}
trap 'exit 124' TERM
trap capture_failure_evidence EXIT

wait_outside_anr() {
  local file="${RUNNER_TEMP:-/tmp}/espana-system-dialog.xml"
  local result="${RUNNER_TEMP:-/tmp}/espana-system-anr.txt"
  local attempt
  for attempt in $(seq 1 12); do
    ui_dump "${file}"
    if ! grep -Fq "isn't responding" "${file}" && ! grep -Fq "isn\u0027t responding" "${file}"; then
      return 0
    fi

    set +e
    python3 - "${file}" "${package_name}" >"${result}" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET

path, target = sys.argv[1:]
raw = open(path, encoding="utf-8", errors="replace").read()
start = raw.find("<?xml")
if start < 0:
    start = raw.find("<hierarchy")
end = raw.find("</hierarchy>", start)
if start < 0 or end < 0:
    raise SystemExit(2)
root = ET.fromstring(raw[start:end + len("</hierarchy>")])
for node in root.iter("node"):
    text = (node.attrib.get("text") or "").strip()
    if "isn't responding" not in text and "isn\u0027t responding" not in text:
        continue
    suffix = " isn't responding" if text.endswith(" isn't responding") else " isn\u0027t responding"
    owner = text[:-len(suffix)]
    if owner == target:
        print(f"APP_ANR|{text}")
        raise SystemExit(3)

    buttons = {}
    for child in root.iter("node"):
        label = (child.attrib.get("text") or "").strip()
        if label not in ("Wait", "Close app"):
            continue
        match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", child.attrib.get("bounds", ""))
        if match:
            x1, y1, x2, y2 = map(int, match.groups())
            buttons[label] = ((x1+x2)//2, (y1+y2)//2)

    # The Pixel launcher and the Google SDK setup activity are unrelated to
    # the target app. Close their modal ANR dialog; target-app ANRs remain fatal.
    if (
        ("launcher" in owner.lower() or owner == "com.google.android.googlesdksetup")
        and "Close app" in buttons
    ):
        x, y = buttons["Close app"]
        print(f"SYSTEM_ANR_CLOSE|{owner}|{x}|{y}")
        raise SystemExit(0)
    if "Wait" in buttons:
        x, y = buttons["Wait"]
        print(f"SYSTEM_ANR_WAIT|{owner}|{x}|{y}")
        raise SystemExit(0)
    print(f"SYSTEM_ANR_WAIT|{owner}||")
    raise SystemExit(0)
raise SystemExit(1)
PY
    rc=$?
    set -e
    if test "${rc}" -eq 3; then
      echo "FAIL: application ANR detected: $(cat "${result}")"
      cat "${file}"
      exit 1
    fi
    if test "${rc}" -ne 0; then
      echo "FAIL: could not classify Android ANR dialog safely."
      cat "${file}"
      exit 1
    fi

    IFS='|' read -r kind owner action_x action_y <"${result}"
    case "${kind}" in
      SYSTEM_ANR_CLOSE)
        echo "Closing unrelated unresponsive Android system package ${owner} to uncover the app under test"
        if test -n "${action_x}" && test -n "${action_y}"; then
          adb shell input tap "${action_x}" "${action_y}"
        else
          echo "FAIL: Close app action unavailable for unrelated launcher ANR."
          cat "${file}"
          exit 1
        fi
        ;;
      SYSTEM_ANR_WAIT)
        echo "Dismissing unrelated system ANR for ${owner} with Wait"
        if test -n "${action_x}" && test -n "${action_y}"; then
          adb shell input tap "${action_x}" "${action_y}"
        else
          adb shell input keyevent 4
        fi
        ;;
      *)
        echo "FAIL: unexpected Android ANR classification: ${kind}"
        cat "${file}"
        exit 1
        ;;
    esac
    sleep 2
  done
  ui_dump "${file}"
  if grep -Fq "isn't responding" "${file}" || grep -Fq "isn\u0027t responding" "${file}"; then
    echo "FAIL: Android ANR dialog remained after bounded stabilization."
    cat "${file}"
    exit 1
  fi
}

launch_app() {
  adb shell am force-stop "${package_name}"
  adb shell monkey -p "${package_name}" 1 >/tmp/espana-monkey.log 2>&1 || {
    cat /tmp/espana-monkey.log
    exit 1
  }
  sleep 3
  wait_outside_anr
}

if [[ "${offline_mode}" == "online" && "${ANDROID_EMULATOR_CI:-false}" == "true" ]]; then
  echo "Verifying a validated internet connection before the online Mapbox smoke."
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  bash "${script_dir}/ensure_android_emulator_online.sh"
elif [[ "${offline_mode}" == "online" ]]; then
  echo "ANDROID_EMULATOR_NETWORK preflight=skipped reason=not_ci_emulator"
fi

launch_app

if test "${offline_mode}" = "offline"; then
  echo "Enabling airplane mode before offline restart."
  adb shell cmd connectivity airplane-mode enable || {
    adb shell settings put global airplane_mode_on 1
    adb shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state true >/dev/null
  }
  airplane_state="$(adb shell settings get global airplane_mode_on 2>/dev/null | tr -d '\r\n' || true)"
  test "${airplane_state}" = "1"
  echo "Restarting application with network disabled."
  launch_app
fi

ui_dump "${window_file}"
if ! grep -q '<hierarchy' "${window_file}"; then
  echo "FAIL: UIAutomator did not return a hierarchy."
  exit 1
fi

find_mapa_coordinates() {
  python3 - "${window_file}" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET
raw = open(sys.argv[1], encoding="utf-8", errors="replace").read()
start = raw.find("<?xml")
if start < 0:
    start = raw.find("<hierarchy")
end = raw.find("</hierarchy>", start)
if start < 0 or end < 0:
    raise SystemExit(2)
root = ET.fromstring(raw[start:end + len("</hierarchy>")])
candidates = []
for node in root.iter("node"):
    text = (node.attrib.get("text") or "").strip()
    desc = (node.attrib.get("content-desc") or "").strip()
    if text != "Mapa" and desc != "Mapa":
        continue
    match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.attrib.get("bounds", ""))
    if match:
        x1, y1, x2, y2 = map(int, match.groups())
        candidates.append(((y1+y2)//2, (x1+x2)//2))
if not candidates:
    raise SystemExit(1)
y, x = max(candidates)
print(x, y)
PY
}

# A cold Android emulator can spend several seconds rendering Flutter after
# boot/restart. Wait for the actual navigation target rather than assuming
# that a single UIAutomator dump immediately after launch is sufficient.
map_found=0
for attempt in $(seq 1 30); do
  wait_outside_anr
  ui_dump "${window_file}"
  if coords="$(find_mapa_coordinates 2>/dev/null)"; then
    read -r tap_x tap_y <<<"${coords}"
    map_found=1
    break
  fi
  if ! adb shell pidof "${package_name}" >/dev/null 2>&1; then
    echo "FAIL: application process disappeared while waiting for Mapa."
    exit 1
  fi
  echo "Mapa not visible yet; waiting (${attempt}/30)."
  sleep 2
 done

if test "${map_found}" -ne 1; then
  echo "FAIL: Could not find visible Mapa navigation destination after bounded startup wait."
  cat "${window_file}"
  exit 1
fi

echo "Tapping Mapa at ${tap_x},${tap_y}"
adb shell input tap "${tap_x}" "${tap_y}"

# The app can remain the resumed activity while a system ANR dialog owns the
# screen. Prove that the actual Mapbox page (its map-only controls) is visible
# before waiting for SDK events or accepting any screenshot entropy metrics.
map_page_check_file="${RUNNER_TEMP:-/tmp}/espana-map-page-check.txt"
map_page_ready=false
for attempt in $(seq 1 15); do
  wait_outside_anr
  ui_dump "${post_window}"
  if python3 tool/verify_android_map_screen.py "${post_window}" --package "${package_name}" >"${map_page_check_file}" 2>&1; then
    cat "${map_page_check_file}"
    map_page_ready=true
    break
  fi
  echo "MAPBOX_MAP_PAGE_WAIT attempt=${attempt}/15 reason=$(tail -n 1 "${map_page_check_file}" 2>/dev/null || echo unavailable)"
  sleep 2
done
if [[ "${map_page_ready}" != "true" ]]; then
  echo "FAIL: the app did not reach the actual Mapbox map page after tapping Mapa."
  cat "${map_page_check_file}" 2>/dev/null || true
  cat "${post_window}" 2>/dev/null || true
  exit 1
fi

logcat_file="${RUNNER_TEMP:-/tmp}/espana-outdoor-map-logcat.txt"
screenshot_file="${RUNNER_TEMP:-/tmp}/espana-outdoor-map.png"
mapbox_diag_file="${RUNNER_TEMP:-/tmp}/espana-mapbox-diagnostics.txt"
mapbox_wait_seconds="${MAPBOX_RENDER_WAIT_SECONDS:-60}"
if ! [[ "${mapbox_wait_seconds}" =~ ^[1-9][0-9]{0,2}$ ]] || (( mapbox_wait_seconds < 15 || mapbox_wait_seconds > 120 )); then
  echo "ERROR: MAPBOX_RENDER_WAIT_SECONDS must be between 15 and 120."
  exit 2
fi

# Do not capture a transient partial frame immediately after style load.
# Wait for visible tiles, a FULL frame and an idle map; keep evidence on timeout.
mapbox_ready=false
mapbox_poll_count=$(( (mapbox_wait_seconds + 2) / 3 ))
for attempt in $(seq 1 "${mapbox_poll_count}"); do
  adb logcat -d -s flutter:I >"${mapbox_diag_file}"
  if grep -Fq 'MAPBOX_DIAGNOSTIC event=MAP_LOADED' "${mapbox_diag_file}" &&
     grep -Fq 'MAPBOX_DIAGNOSTIC event=MAP_IDLE' "${mapbox_diag_file}" &&
     grep -Fq 'MAPBOX_DIAGNOSTIC event=RENDER_FRAME mode=RenderMode.FULL' "${mapbox_diag_file}"; then
    mapbox_ready=true
    echo "MAPBOX_RENDER_READY elapsed_seconds=$((attempt * 3)) map_loaded=true full_frame=true idle=true"
    break
  fi
  if (( attempt % 5 == 0 )); then
    echo "MAPBOX_RENDER_WAIT elapsed_seconds=$((attempt * 3)) map_loaded=$(grep -Fc 'MAPBOX_DIAGNOSTIC event=MAP_LOADED' "${mapbox_diag_file}" || true) full_frame=$(grep -Fc 'MAPBOX_DIAGNOSTIC event=RENDER_FRAME mode=RenderMode.FULL' "${mapbox_diag_file}" || true) idle=$(grep -Fc 'MAPBOX_DIAGNOSTIC event=MAP_IDLE' "${mapbox_diag_file}" || true)"
  fi
  sleep 3
done
if [[ "${mapbox_ready}" != "true" ]]; then
  echo "MAPBOX_RENDER_NOT_READY deadline_seconds=${mapbox_wait_seconds}"
  grep 'MAPBOX_DIAGNOSTIC' "${mapbox_diag_file}" | tail -n 80 || true
fi

# Recheck the real map page immediately before capture. This also rejects
# Android system dialogs whose underlying app task still appears resumed.
wait_outside_anr
ui_dump "${post_window}"
python3 tool/verify_android_map_screen.py "${post_window}" --package "${package_name}"

# The process can remain alive in the background while the launcher or a
# system dialog owns the screen. Never accept a screenshot without proving
# that the application under test is the resumed/focused package.
foreground_dump="$(adb shell dumpsys window windows 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | tr -d '\r' || true)"
if ! grep -Fq "${package_name}" <<<"${foreground_dump}"; then
  foreground_dump="$(adb shell dumpsys activity activities 2>/dev/null | grep -E 'mResumedActivity|topResumedActivity' | tr -d '\r' || true)"
fi
if ! grep -Fq "${package_name}" <<<"${foreground_dump}"; then
  echo "FAIL: application is not the foreground Android package."
  printf '%s\n' "${foreground_dump}"
  exit 1
fi
echo "MAP_SMOKE_FOREGROUND package=${package_name} verified=true"

adb logcat -d >"${logcat_file}"
adb exec-out screencap -p >"${screenshot_file}"
test -s "${screenshot_file}"

pid="$(adb shell pidof "${package_name}" 2>/dev/null | tr -d '\r\n' || true)"
test -n "${pid}" || {
  echo "FAIL: application process is not alive after tapping Mapa."
  grep -Ein "FATAL EXCEPTION|Fatal signal|SIGSEGV|SIGABRT|Abort message:|backtrace:|AndroidRuntime|Mapbox|MapboxSDK|MapboxStyle" "${logcat_file}" | tail -n 400 || true
  exit 1
}

if grep -Eiq "FATAL EXCEPTION|Fatal signal [0-9]+ \((SIGSEGV|SIGABRT)\)|Abort message:|backtrace:" "${logcat_file}"; then
  echo "FAIL: native/application crash detected after tapping Mapa."
  grep -Ein "FATAL EXCEPTION|Fatal signal|SIGSEGV|SIGABRT|Abort message:|backtrace:|AndroidRuntime|Mapbox|MapboxSDK|MapboxStyle" "${logcat_file}" | tail -n 500 || true
  exit 1
fi

ui_dump "${post_window}"
if grep -Fq 'No se pudo cargar el mapa' "${post_window}" || grep -Fq 'Reintentar' "${post_window}"; then
  echo "FAIL: Mapbox is showing the map loader error state."
  cat "${post_window}"
  grep -Ein "MapboxException|StyleManager|HTTP [0-9]{3}|Range|Mapbox|MapboxSDK|MapboxStyle" "${logcat_file}" | tail -n 500 || true
  exit 1
fi
if grep -Eiq "MapboxException|StyleManager" "${logcat_file}"; then
  echo "FAIL: Mapbox style exception detected."
  grep -Ein "MapboxException|StyleManager|HTTP [0-9]{3}|Range|Mapbox|MapboxSDK|MapboxStyle" "${logcat_file}" | tail -n 500 || true
  exit 1
fi

# A live process and absence of a loader message do not prove that the
# cartographic viewport rendered. Reject blank/partial maps before uploading
# the smoke evidence or reporting a successful Android staging run.
set +e
python3 tool/verify_android_map_screenshot.py "${screenshot_file}" --foreground-package "${package_name}"
screenshot_status=$?
set -e

if [[ "${mapbox_ready}" != "true" ]]; then
  echo "FAIL: Mapbox did not reach MAP_LOADED + FULL_FRAME + MAP_IDLE before the bounded render deadline."
  exit 1
fi
if (( screenshot_status != 0 )); then
  exit "${screenshot_status}"
fi

echo "PASS: Mapbox reached a complete idle viewport and the screenshot passed the visual gate."
grep -Ei "Mapbox|MapboxSDK|MapboxStyle|tile|Range" "${logcat_file}" | tail -n 200 || true
