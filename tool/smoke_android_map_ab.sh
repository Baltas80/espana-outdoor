#!/usr/bin/env bash
set -euo pipefail

runner_temp="${1:?RUNNER_TEMP path required}"
primary_style="${2:-mapbox://styles/mapbox/outdoors-v12}"
primary_apk="${runner_temp}/primary-build/app-release.apk"
standard_apk="${runner_temp}/standard-build/app-release.apk"
primary_manifest="${runner_temp}/primary-build/android-staging-validation.txt"
standard_manifest="${runner_temp}/standard-build/android-staging-validation.txt"
primary_evidence="${runner_temp}/primary"
standard_evidence="${runner_temp}/standard"

mkdir -p "${primary_evidence}" "${standard_evidence}"

manifest_value() {
  local manifest="$1"
  local key="$2"
  sed -n "s/^${key}=//p" "${manifest}" | head -n 1
}

if [[ ! -s "${primary_apk}" || ! -s "${primary_manifest}" ]]; then
  echo "ERROR: verified primary APK/manifest is missing." >&2
  exit 2
fi
primary_app_id="$(manifest_value "${primary_manifest}" application_id)"
primary_source_commit="$(manifest_value "${primary_manifest}" source_commit)"
primary_version_code="$(manifest_value "${primary_manifest}" version_code)"
primary_manifest_style="$(manifest_value "${primary_manifest}" mapbox_style_uri)"
if [[ -z "${primary_app_id}" || -z "${primary_source_commit}" || -z "${primary_version_code}" ]]; then
  echo "ERROR: primary manifest is missing application_id, source_commit or version_code." >&2
  exit 2
fi
if [[ -n "${primary_manifest_style}" && "${primary_manifest_style}" != "${primary_style}" ]]; then
  echo "ERROR: primary style argument does not match the APK manifest." >&2
  exit 2
fi

primary_status=0
RUNNER_TEMP="${primary_evidence}" timeout --foreground --signal=TERM --kill-after=150s 20m \
  bash tool/smoke_android_map.sh "${primary_apk}" online || primary_status=$?

standard_status=0
standard_run=false
if [[ -s "${standard_apk}" ]]; then
  if [[ ! -s "${standard_manifest}" ]]; then
    echo "ERROR: Standard APK exists without its validation manifest." >&2
    exit 2
  fi
  standard_app_id="$(manifest_value "${standard_manifest}" application_id)"
  standard_source_commit="$(manifest_value "${standard_manifest}" source_commit)"
  standard_version_code="$(manifest_value "${standard_manifest}" version_code)"
  standard_manifest_style="$(manifest_value "${standard_manifest}" mapbox_style_uri)"
  if [[ "${standard_app_id}" != "${primary_app_id}" || "${standard_source_commit}" != "${primary_source_commit}" || "${standard_version_code}" != "${primary_version_code}" ]]; then
    echo "ERROR: A/B APKs do not share application ID, source commit and version code." >&2
    exit 2
  fi
  if [[ "${standard_manifest_style}" != "mapbox://styles/mapbox/standard" ]]; then
    echo "ERROR: comparison APK manifest does not identify Mapbox Standard." >&2
    exit 2
  fi
  # Both APKs share an application ID. Clear the primary app data before
  # installing Standard so its TileStore/style cache cannot inherit Outdoors.
  timeout --foreground --signal=TERM --kill-after=15s 45s adb shell am force-stop "${primary_app_id}"
  clear_output="$(timeout --foreground --signal=TERM --kill-after=15s 45s adb shell pm clear "${primary_app_id}" | tr -d "\r")"
  if ! grep -Fxq "Success" <<<"${clear_output}"; then
    echo "ERROR: failed to clear app data between A/B styles: ${clear_output}" >&2
    exit 2
  fi
  standard_run=true
  RUNNER_TEMP="${standard_evidence}" timeout --foreground --signal=TERM --kill-after=150s 20m \
    bash tool/smoke_android_map.sh "${standard_apk}" online || standard_status=$?
fi

echo "MAPBOX_STYLE_AB primary_style=${primary_style} primary_status=${primary_status} standard_run=${standard_run} standard_status=${standard_status}"
if (( primary_status != 0 || standard_status != 0 )); then
  exit 1
fi
