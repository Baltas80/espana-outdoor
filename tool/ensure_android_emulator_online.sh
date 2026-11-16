#!/usr/bin/env bash
# Restore and verify internet connectivity on a CI Android emulator.
# This is opt-in and is never used by the physical-device validation script.
set -Eeuo pipefail

if [[ "${ANDROID_EMULATOR_CI:-false}" != "true" ]]; then
  echo "ANDROID_EMULATOR_NETWORK preflight=skipped reason=not_ci_emulator"
  exit 0
fi

DEVICE_SERIAL="${ANDROID_SERIAL:-emulator-5554}"
ADB_COMMAND="${ADB:-adb}"
TIMEOUT_SECONDS="${ANDROID_EMULATOR_NETWORK_TIMEOUT_SECONDS:-90}"
WIFI_CONNECT_WAIT_SECONDS="${ANDROID_EMULATOR_WIFI_CONNECT_WAIT_SECONDS:-15}"

if ! [[ "${TIMEOUT_SECONDS}" =~ ^[1-9][0-9]{0,2}$ ]]; then
  echo "ERROR: ANDROID_EMULATOR_NETWORK_TIMEOUT_SECONDS must be between 1 and 999."
  exit 2
fi
if ! [[ "${WIFI_CONNECT_WAIT_SECONDS}" =~ ^[1-9][0-9]{0,2}$ ]]; then
  echo "ERROR: ANDROID_EMULATOR_WIFI_CONNECT_WAIT_SECONDS must be between 1 and 999."
  exit 2
fi
if ! command -v "${ADB_COMMAND}" >/dev/null 2>&1; then
  echo "ERROR: adb executable was not found."
  exit 2
fi

"${ADB_COMMAND}" -s "${DEVICE_SERIAL}" get-state | grep -qx device

# Leave airplane mode, enable radios, and start a Wi-Fi scan.
"${ADB_COMMAND}" -s "${DEVICE_SERIAL}" shell cmd connectivity airplane-mode disable >/dev/null 2>&1 || true
"${ADB_COMMAND}" -s "${DEVICE_SERIAL}" shell settings put global airplane_mode_on 0 >/dev/null 2>&1 || true
"${ADB_COMMAND}" -s "${DEVICE_SERIAL}" shell am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false >/dev/null 2>&1 || true
"${ADB_COMMAND}" -s "${DEVICE_SERIAL}" shell svc wifi enable >/dev/null 2>&1 || true
"${ADB_COMMAND}" -s "${DEVICE_SERIAL}" shell svc data enable >/dev/null 2>&1 || true
"${ADB_COMMAND}" -s "${DEVICE_SERIAL}" shell cmd wifi start-scan >/dev/null 2>&1 || true

wifi_status="$("${ADB_COMMAND}" -s "${DEVICE_SERIAL}" shell cmd wifi status 2>/dev/null || true)"
if ! grep -qi 'Wifi is connected' <<<"${wifi_status}"; then
  # Emulator images commonly expose host NAT as VirtWifi; some use AndroidWifi.
  for ssid in VirtWifi AndroidWifi; do
    echo "ANDROID_EMULATOR_NETWORK wifi_connect_attempt ssid=${ssid}"
    "${ADB_COMMAND}" -s "${DEVICE_SERIAL}" shell cmd wifi connect-network "${ssid}" open >/dev/null 2>&1 || true
    for connect_attempt in $(seq 1 "${WIFI_CONNECT_WAIT_SECONDS}"); do
      wifi_status="$("${ADB_COMMAND}" -s "${DEVICE_SERIAL}" shell cmd wifi status 2>/dev/null || true)"
      if grep -qi 'Wifi is connected' <<<"${wifi_status}"; then
        echo "ANDROID_EMULATOR_NETWORK wifi_connected=1"
        break 2
      fi
      sleep 1
    done
  done
fi

for attempt in $(seq 1 "${TIMEOUT_SECONDS}"); do
  airplane_state="$("${ADB_COMMAND}" -s "${DEVICE_SERIAL}" shell settings get global airplane_mode_on 2>/dev/null | tr -d '\r\n' || true)"
  wifi_status="$("${ADB_COMMAND}" -s "${DEVICE_SERIAL}" shell cmd wifi status 2>/dev/null || true)"
  connectivity="$("${ADB_COMMAND}" -s "${DEVICE_SERIAL}" shell dumpsys connectivity 2>/dev/null || true)"
  wifi_connected=0
  active_default=0
  validated_internet=0
  if grep -qi 'Wifi is connected' <<<"${wifi_status}"; then wifi_connected=1; fi
  if grep -Eq '^Active default network: [0-9]+' <<<"${connectivity}"; then active_default=1; fi
  if grep -Eq '(NetworkCapabilities|Capabilities):.*INTERNET' <<<"${connectivity}" && grep -Eq '(NetworkCapabilities|Capabilities):.*VALIDATED' <<<"${connectivity}"; then
    validated_internet=1
  fi
  if [[ "${airplane_state}" == "0" && "${wifi_connected}" == "1" && "${active_default}" == "1" && "${validated_internet}" == "1" ]]; then
    echo "ANDROID_EMULATOR_NETWORK online=validated wifi=connected attempt=${attempt} airplane_mode=off"
    exit 0
  fi
  sleep 1
done

echo "ERROR: Android emulator did not obtain a connected, validated internet default network within ${TIMEOUT_SECONDS}s."
echo "airplane_mode=${airplane_state:-unknown}"
echo "wifi_state=$("${ADB_COMMAND}" -s "${DEVICE_SERIAL}" shell settings get global wifi_on 2>/dev/null | tr -d '\r\n' || true)"
echo "wifi_status=${wifi_status:-unavailable}"
echo "wifi_scan_results:"
"${ADB_COMMAND}" -s "${DEVICE_SERIAL}" shell cmd wifi list-scan-results 2>/dev/null | head -n 20 || true
echo "ip_route:"
"${ADB_COMMAND}" -s "${DEVICE_SERIAL}" shell ip route 2>/dev/null | head -n 20 || true
echo "connectivity_diagnostics:"
grep -E 'Active default network:|NetworkAgentInfo.*CONNECTED|NetworkCapabilities:|Capabilities:' <<<"${connectivity}" | head -n 40 || true
exit 1
