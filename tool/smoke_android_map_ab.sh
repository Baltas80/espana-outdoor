#!/usr/bin/env bash
set -euo pipefail

runner_temp="${1:?RUNNER_TEMP path required}"
primary_style="${2:-mapbox://styles/mapbox/outdoors-v12}"
primary_apk="${runner_temp}/primary-build/app-release.apk"
standard_apk="${runner_temp}/standard-build/app-release.apk"
primary_evidence="${runner_temp}/primary"
standard_evidence="${runner_temp}/standard"

mkdir -p "${primary_evidence}" "${standard_evidence}"

if [[ ! -s "${primary_apk}" ]]; then
  echo "ERROR: verified primary APK is missing: ${primary_apk}" >&2
  exit 2
fi

primary_status=0
RUNNER_TEMP="${primary_evidence}" timeout --foreground --signal=TERM --kill-after=150s 20m \
  bash tool/smoke_android_map.sh "${primary_apk}" online || primary_status=$?

standard_status=0
standard_run=false
if [[ -s "${standard_apk}" ]]; then
  standard_run=true
  RUNNER_TEMP="${standard_evidence}" timeout --foreground --signal=TERM --kill-after=150s 20m \
    bash tool/smoke_android_map.sh "${standard_apk}" online || standard_status=$?
fi

echo "MAPBOX_STYLE_AB primary_style=${primary_style} primary_status=${primary_status} standard_run=${standard_run} standard_status=${standard_status}"
if (( primary_status != 0 || standard_status != 0 )); then
  exit 1
fi
