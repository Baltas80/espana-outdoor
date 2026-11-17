#!/usr/bin/env bash
set -euo pipefail

runner_temp="${1:?RUNNER_TEMP path required}"
primary_style="${2:-mapbox://styles/mapbox/outdoors-v12}"
primary_apk="${runner_temp}/primary-build/app-release.apk"
renderer_apk="${runner_temp}/texture-vd-build/app-release.apk"
primary_manifest="${runner_temp}/primary-build/android-staging-validation.txt"
renderer_manifest="${runner_temp}/texture-vd-build/android-staging-validation.txt"
primary_evidence="${runner_temp}/primary"
renderer_evidence="${runner_temp}/texture-vd"

mkdir -p "${primary_evidence}" "${renderer_evidence}"

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
primary_view_mode="$(manifest_value "${primary_manifest}" mapbox_android_view_mode)"
if [[ -z "${primary_app_id}" || -z "${primary_source_commit}" || -z "${primary_version_code}" ]]; then
  echo "ERROR: primary manifest is missing application_id, source_commit or version_code." >&2
  exit 2
fi
if [[ "${primary_manifest_style}" != "${primary_style}" ]]; then
  echo "ERROR: primary style argument does not match the APK manifest." >&2
  exit 2
fi
if [[ "${primary_view_mode}" != "hybrid-surface" ]]; then
  echo "ERROR: primary APK must use the production Hybrid Composition/SurfaceView mode." >&2
  exit 2
fi

primary_status=0
RUNNER_TEMP="${primary_evidence}" timeout --foreground --signal=TERM --kill-after=150s 20m \
  bash tool/smoke_android_map.sh "${primary_apk}" online || primary_status=$?

renderer_status=0
renderer_run=false
if [[ -s "${renderer_apk}" ]]; then
  if [[ ! -s "${renderer_manifest}" ]]; then
    echo "ERROR: TextureView/VD APK exists without its validation manifest." >&2
    exit 2
  fi
  renderer_app_id="$(manifest_value "${renderer_manifest}" application_id)"
  renderer_source_commit="$(manifest_value "${renderer_manifest}" source_commit)"
  renderer_version_code="$(manifest_value "${renderer_manifest}" version_code)"
  renderer_manifest_style="$(manifest_value "${renderer_manifest}" mapbox_style_uri)"
  renderer_view_mode="$(manifest_value "${renderer_manifest}" mapbox_android_view_mode)"
  if [[ "${renderer_app_id}" != "${primary_app_id}" || "${renderer_source_commit}" != "${primary_source_commit}" || "${renderer_version_code}" != "${primary_version_code}" ]]; then
    echo "ERROR: renderer comparison APKs do not share application ID, source commit and version code." >&2
    exit 2
  fi
  if [[ "${renderer_manifest_style}" != "${primary_manifest_style}" ]]; then
    echo "ERROR: renderer comparison must use the same Mapbox style as the primary APK." >&2
    exit 2
  fi
  if [[ "${renderer_view_mode}" != "virtual-texture" ]]; then
    echo "ERROR: comparison APK manifest does not identify Virtual Display/TextureView mode." >&2
    exit 2
  fi

  # Both APKs share an application ID. Clear the primary app data before
  # installing the renderer comparison so its TileStore/style cache is isolated.
  timeout --foreground --signal=TERM --kill-after=15s 45s adb shell am force-stop "${primary_app_id}"
  clear_output="$(timeout --foreground --signal=TERM --kill-after=15s 45s adb shell pm clear "${primary_app_id}" | tr -d "\r")"
  if ! grep -Fxq "Success" <<<"${clear_output}"; then
    echo "ERROR: failed to clear app data between renderer experiments: ${clear_output}" >&2
    exit 2
  fi
  renderer_run=true
  RUNNER_TEMP="${renderer_evidence}" timeout --foreground --signal=TERM --kill-after=150s 20m \
    bash tool/smoke_android_map.sh "${renderer_apk}" online || renderer_status=$?
fi

echo "MAPBOX_RENDERER_AB style=${primary_style} primary_mode=hybrid-surface primary_status=${primary_status} comparison_run=${renderer_run} comparison_mode=virtual-texture comparison_status=${renderer_status}"
if (( primary_status != 0 || renderer_status != 0 )); then
  exit 1
fi
