#!/usr/bin/env bash
# Run the critical native route/download/offline proof first, then the
# independent release-APK map smoke, on one emulator boot. Both checks always
# run when the runner remains available; one failure does not suppress the other.
set -u -o pipefail

apk_path="${1:?APK path required}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

route_status=0
smoke_status=0

echo "ANDROID_VALIDATION_PHASE_START phase=online_offline_routing"
if bash "${script_dir}/staging_android_route_integration.sh"; then
  echo "ANDROID_VALIDATION_PHASE_RESULT phase=online_offline_routing result=success"
else
  route_status=$?
  echo "ANDROID_VALIDATION_PHASE_RESULT phase=online_offline_routing result=failure exit=${route_status}"
fi

echo "ANDROID_VALIDATION_PHASE_START phase=map_smoke"
if bash "${script_dir}/smoke_android_map.sh" "${apk_path}" online; then
  echo "ANDROID_VALIDATION_PHASE_RESULT phase=map_smoke result=success"
else
  smoke_status=$?
  echo "ANDROID_VALIDATION_PHASE_RESULT phase=map_smoke result=failure exit=${smoke_status}"
fi

echo "ANDROID_VALIDATION_SUMMARY route_integration_exit=${route_status} map_smoke_exit=${smoke_status}"
if [[ "${route_status}" -ne 0 || "${smoke_status}" -ne 0 ]]; then
  exit 1
fi
