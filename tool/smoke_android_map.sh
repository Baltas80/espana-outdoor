#!/usr/bin/env bash
set -euo pipefail

apk_path="${1:?APK path required}"
offline_mode="${2:-online}"
aapt_path="$(find "${ANDROID_HOME}/build-tools" -maxdepth 2 -type f -name aapt -print | sort -V | tail -n 1)"
test -x "${aapt_path}"
package_name="$("${aapt_path}" dump badging "${apk_path}" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -n 1)"
test -n "${package_name}"

echo "Installing ${package_name}"
adb wait-for-device
adb install -r "${apk_path}"

ui_dump() {
  local file="$1"
  adb exec-out uiautomator dump /dev/tty 2>/dev/null >"${file}" || true
}

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
    for child in root.iter("node"):
        if (child.attrib.get("text") or "").strip() != "Wait":
            continue
        match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", child.attrib.get("bounds", ""))
        if match:
            x1, y1, x2, y2 = map(int, match.groups())
            print(f"SYSTEM_ANR|{owner}|{(x1+x2)//2}|{(y1+y2)//2}")
            raise SystemExit(0)
    print(f"SYSTEM_ANR|{owner}||")
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

    IFS='|' read -r kind owner wait_x wait_y <"${result}"
    test "${kind}" = "SYSTEM_ANR"
    if test -n "${wait_x}" && test -n "${wait_y}"; then
      echo "Dismissing system ANR for ${owner} with Wait"
      adb shell input tap "${wait_x}" "${wait_y}"
    else
      adb shell input keyevent 4
    fi
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

window_file="${RUNNER_TEMP:-/tmp}/espana-window.xml"
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
sleep 15

logcat_file="${RUNNER_TEMP:-/tmp}/espana-outdoor-map-logcat.txt"
screenshot_file="${RUNNER_TEMP:-/tmp}/espana-outdoor-map.png"
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

post_window="${RUNNER_TEMP:-/tmp}/espana-window-post-map.xml"
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

echo "PASS: Mapbox map remained alive and the visible UI is not in the loader error state."
grep -Ei "Mapbox|MapboxSDK|MapboxStyle|tile|Range" "${logcat_file}" | tail -n 200 || true
