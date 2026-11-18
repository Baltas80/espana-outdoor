#!/usr/bin/env bash
# Restore and verify internet connectivity on a CI Android emulator.
# Every adb invocation is bounded so an unresponsive emulator cannot hold the job indefinitely.
# This is opt-in and is never used by the physical-device validation script.
set -Eeuo pipefail

if [[ "${ANDROID_EMULATOR_CI:-false}" != "true" ]]; then
  echo "ANDROID_EMULATOR_NETWORK preflight=skipped reason=not_ci_emulator"
  exit 0
fi

DEVICE_SERIAL="${ANDROID_SERIAL:-emulator-5554}"
ADB_COMMAND="${ADB:-adb}"
TIMEOUT_SECONDS="${ANDROID_EMULATOR_NETWORK_TIMEOUT_SECONDS:-90}"
WIFI_CONNECT_WAIT_SECONDS="${ANDROID_EMULATOR_WIFI_CONNECT_WAIT_SECONDS:-8}"
ADB_COMMAND_TIMEOUT_SECONDS="${ANDROID_ADB_COMMAND_TIMEOUT_SECONDS:-5}"

for setting in TIMEOUT_SECONDS WIFI_CONNECT_WAIT_SECONDS ADB_COMMAND_TIMEOUT_SECONDS; do
  value="${!setting}"
  if ! [[ "${value}" =~ ^[1-9][0-9]{0,2}$ ]]; then
    echo "ERROR: ${setting} must be a positive integer between 1 and 999."
    exit 2
  fi
done
if (( ADB_COMMAND_TIMEOUT_SECONDS > 30 )); then
  echo "ERROR: ADB_COMMAND_TIMEOUT_SECONDS must not exceed 30 seconds."
  exit 2
fi
if ! command -v "${ADB_COMMAND}" >/dev/null 2>&1; then
  echo "ERROR: adb executable was not found."
  exit 2
fi
if ! command -v timeout >/dev/null 2>&1; then
  echo "ERROR: GNU timeout is required to bound Android emulator commands."
  exit 2
fi

adb_run() {
  timeout --foreground --signal=TERM --kill-after=3s "${ADB_COMMAND_TIMEOUT_SECONDS}s" \
    "${ADB_COMMAND}" -s "${DEVICE_SERIAL}" "$@"
}

if ! adb_run get-state | grep -qx device; then
  echo "ERROR: Android emulator is not in device state."
  exit 1
fi

# Restore radios in one bounded shell command. Individual operations may be
# unsupported by an emulator image, so their failures are intentionally ignored.
adb_run shell 'cmd connectivity airplane-mode disable >/dev/null 2>&1 || true
settings put global airplane_mode_on 0 >/dev/null 2>&1 || true
am broadcast -a android.intent.action.AIRPLANE_MODE --ez state false >/dev/null 2>&1 || true
svc wifi enable >/dev/null 2>&1 || true
svc data enable >/dev/null 2>&1 || true
cmd wifi start-scan >/dev/null 2>&1 || true'

wifi_status="$(adb_run shell cmd wifi status 2>/dev/null || true)"
if ! grep -qi 'Wifi is connected' <<<"${wifi_status}"; then
  # Emulator images commonly expose host NAT as VirtWifi; some use AndroidWifi.
  for ssid in VirtWifi AndroidWifi; do
    echo "ANDROID_EMULATOR_NETWORK wifi_connect_attempt ssid=${ssid}"
    adb_run shell cmd wifi connect-network "${ssid}" open >/dev/null 2>&1 || true
    for connect_attempt in $(seq 1 "${WIFI_CONNECT_WAIT_SECONDS}"); do
      if ! wifi_status="$(adb_run shell cmd wifi status 2>/dev/null)"; then
        echo "ERROR: adb wifi status failed or timed out."
        exit 1
      fi
      if grep -qi 'Wifi is connected' <<<"${wifi_status}"; then
        echo "ANDROID_EMULATOR_NETWORK wifi_connected=1"
        break 2
      fi
      sleep 1
    done
  done
fi

snapshot=""
for attempt in $(seq 1 "${TIMEOUT_SECONDS}"); do
  # One bounded adb round-trip per poll. If dumpsys itself hangs, fail with a
  # useful timeout instead of multiplying an unbounded adb call across 90 polls.
  snapshot="$(adb_run shell 'printf "AIRPLANE_MODE="; settings get global airplane_mode_on
printf "\nWIFI_STATUS_BEGIN\n"; cmd wifi status
printf "\nCONNECTIVITY_BEGIN\n"; dumpsys connectivity')"
  airplane_state="$(sed -n 's/^AIRPLANE_MODE=//p' <<<"${snapshot}" | head -n 1 | tr -d '\r')"
  wifi_block="$(sed -n '/^WIFI_STATUS_BEGIN$/,/^CONNECTIVITY_BEGIN$/p' <<<"${snapshot}")"
  connectivity="$(sed -n '/^CONNECTIVITY_BEGIN$/,$p' <<<"${snapshot}")"

  wifi_connected=0
  active_default=0
  validated_internet=0
  if grep -qi 'Wifi is connected' <<<"${wifi_block}"; then wifi_connected=1; fi
  if grep -Eq 'Active default network: [0-9]+' <<<"${connectivity}"; then active_default=1; fi
  if grep -Eq '(NetworkCapabilities|Capabilities):.*INTERNET' <<<"${connectivity}" && \
     grep -Eq '(NetworkCapabilities|Capabilities):.*VALIDATED' <<<"${connectivity}"; then
    validated_internet=1
  fi
  if [[ "${airplane_state}" == "0" && "${wifi_connected}" == "1" && \
        "${active_default}" == "1" && "${validated_internet}" == "1" ]]; then
    echo "ANDROID_EMULATOR_NETWORK online=validated wifi=connected attempt=${attempt} airplane_mode=off"
    exit 0
  fi
  sleep 1
done

echo "ERROR: Android emulator did not obtain a connected, validated internet default network within ${TIMEOUT_SECONDS}s."
echo "airplane_mode=${airplane_state:-unknown}"
echo "airplane_mode=${airplane_state:-unknown}"
echo "wifi_status=${wifi_block:-unavailable}"
echo "wifi_scan_results:"
adb_run shell cmd wifi list-scan-results 2>/dev/null | head -n 20 || true
echo "ip_route:"
adb_run shell ip route 2>/dev/null | head -n 20 || true
echo "connectivity_diagnostics:"
grep -E 'Active default network:|NetworkAgentInfo.*CONNECTED|NetworkCapabilities:|Capabilities:' <<<"${connectivity}" | head -n 40 || true
exit 1
