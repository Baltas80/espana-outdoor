#!/usr/bin/env bash
set -euo pipefail

runner_temp="${1:?RUNNER_TEMP path required}"
primary_style="${2:-mapbox://styles/mapbox/outdoors-v12}"
primary_apk="${runner_temp}/primary-build/app-release.apk"
renderer_apk="${runner_temp}/skia-build/app-release.apk"
primary_manifest="${runner_temp}/primary-build/android-staging-validation.txt"
renderer_manifest="${runner_temp}/skia-build/android-staging-validation.txt"
primary_evidence="${runner_temp}/primary"
renderer_evidence="${runner_temp}/skia"
tile_store_disabled_apk="${runner_temp}/tile-store-disabled-build/app-release.apk"
tile_store_disabled_manifest="${runner_temp}/tile-store-disabled-build/android-staging-validation.txt"
tile_store_disabled_evidence="${runner_temp}/tile-store-disabled"

mkdir -p "${primary_evidence}" "${renderer_evidence}" "${tile_store_disabled_evidence}"

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
primary_renderer="$(manifest_value "${primary_manifest}" flutter_renderer)"
primary_impeller="$(manifest_value "${primary_manifest}" impeller_enabled)"
primary_tile_store_mode="$(manifest_value "${primary_manifest}" mapbox_tile_store_usage_mode)"
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
if [[ "${primary_renderer}" != "impeller-default" || "${primary_impeller}" != "default" ]]; then
  echo "ERROR: primary APK manifest must identify the default Impeller configuration." >&2
  exit 2
fi
if [[ "${primary_tile_store_mode}" != "default" ]]; then
  echo "ERROR: primary APK must use the default TileStore mode." >&2
  exit 2
fi

primary_status=0
RUNNER_TEMP="${primary_evidence}" timeout --foreground --signal=TERM --kill-after=150s 20m \
  bash tool/smoke_android_map.sh "${primary_apk}" online || primary_status=$?

renderer_status=0
renderer_run=false
if [[ -s "${renderer_apk}" ]]; then
  if [[ ! -s "${renderer_manifest}" ]]; then
    echo "ERROR: Skia comparison APK exists without its validation manifest." >&2
    exit 2
  fi
  renderer_app_id="$(manifest_value "${renderer_manifest}" application_id)"
  renderer_source_commit="$(manifest_value "${renderer_manifest}" source_commit)"
  renderer_version_code="$(manifest_value "${renderer_manifest}" version_code)"
  renderer_manifest_style="$(manifest_value "${renderer_manifest}" mapbox_style_uri)"
  renderer_view_mode="$(manifest_value "${renderer_manifest}" mapbox_android_view_mode)"
  comparison_renderer="$(manifest_value "${renderer_manifest}" flutter_renderer)"
  comparison_impeller="$(manifest_value "${renderer_manifest}" impeller_enabled)"
  if [[ "${renderer_app_id}" != "${primary_app_id}" || "${renderer_source_commit}" != "${primary_source_commit}" || "${renderer_version_code}" != "${primary_version_code}" ]]; then
    echo "ERROR: comparison APKs do not share application ID, source commit and version code." >&2
    exit 2
  fi
  if [[ "${renderer_manifest_style}" != "${primary_manifest_style}" ]]; then
    echo "ERROR: Skia comparison must use the same Mapbox style as the primary APK." >&2
    exit 2
  fi
  if [[ "${renderer_view_mode}" != "${primary_view_mode}" ]]; then
    echo "ERROR: Skia comparison must use the same Android hosting mode as the primary APK." >&2
    exit 2
  fi
  if [[ "${comparison_renderer}" != "skia-optout" || "${comparison_impeller}" != "false" ]]; then
    echo "ERROR: comparison APK manifest does not identify the Skia/Impeller opt-out build." >&2
    exit 2
  fi

  # Both APKs share an application ID. Clear the primary app data before
  # installing the Skia comparison so its TileStore/style cache is isolated.
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

tile_store_disabled_status=0
tile_store_disabled_run=false
if [[ -s "${tile_store_disabled_apk}" ]]; then
  if [[ ! -s "${tile_store_disabled_manifest}" ]]; then
    echo "ERROR: TileStore-disabled diagnostic APK exists without its validation manifest." >&2
    exit 2
  fi
  diagnostic_app_id="$(manifest_value "${tile_store_disabled_manifest}" application_id)"
  diagnostic_source_commit="$(manifest_value "${tile_store_disabled_manifest}" source_commit)"
  diagnostic_version_code="$(manifest_value "${tile_store_disabled_manifest}" version_code)"
  diagnostic_style="$(manifest_value "${tile_store_disabled_manifest}" mapbox_style_uri)"
  diagnostic_view_mode="$(manifest_value "${tile_store_disabled_manifest}" mapbox_android_view_mode)"
  diagnostic_tile_store_mode="$(manifest_value "${tile_store_disabled_manifest}" mapbox_tile_store_usage_mode)"
  if [[ "${diagnostic_app_id}" != "${primary_app_id}" || "${diagnostic_source_commit}" != "${primary_source_commit}" || "${diagnostic_version_code}" != "${primary_version_code}" ]]; then
    echo "ERROR: TileStore diagnostic APK does not share application ID, source commit and version code." >&2
    exit 2
  fi
  if [[ "${diagnostic_style}" != "${primary_manifest_style}" || "${diagnostic_view_mode}" != "${primary_view_mode}" ]]; then
    echo "ERROR: TileStore diagnostic APK must keep the primary style and Android hosting mode." >&2
    exit 2
  fi
  if [[ "${diagnostic_tile_store_mode}" != "disabled" ]]; then
    echo "ERROR: diagnostic APK manifest must identify TileStore usage as disabled." >&2
    exit 2
  fi

  # The diagnostic build intentionally bypasses TileStore. It must never be
  # used as an offline acceptance candidate.
  timeout --foreground --signal=TERM --kill-after=15s 45s adb shell am force-stop "${primary_app_id}"
  clear_output="$(timeout --foreground --signal=TERM --kill-after=15s 45s adb shell pm clear "${primary_app_id}" | tr -d "\r")"
  if ! grep -Fxq "Success" <<<"${clear_output}"; then
    echo "ERROR: failed to clear app data before TileStore-disabled experiment: ${clear_output}" >&2
    exit 2
  fi
  tile_store_disabled_run=true
  RUNNER_TEMP="${tile_store_disabled_evidence}" timeout --foreground --signal=TERM --kill-after=150s 20m \
    bash tool/smoke_android_map.sh "${tile_store_disabled_apk}" online || tile_store_disabled_status=$?
fi

primary_renderer_status=0
primary_logcat="${primary_evidence}/espana-outdoor-map-logcat.txt"
if [[ ! -s "${primary_logcat}" ]] || ! grep -Fq "MAPBOX_DIAGNOSTIC event=FLUTTER_RENDERER backend=impeller" "${primary_logcat}"; then
  echo "ERROR: primary APK did not prove that Impeller is active in the runtime log." >&2
  primary_renderer_status=1
fi

comparison_renderer_status=0
if [[ "${renderer_run}" == "true" ]]; then
  comparison_logcat="${renderer_evidence}/espana-outdoor-map-logcat.txt"
  if [[ ! -s "${comparison_logcat}" ]] || ! grep -Fq "MAPBOX_DIAGNOSTIC event=FLUTTER_RENDERER backend=skia" "${comparison_logcat}"; then
    echo "ERROR: comparison APK did not prove that Skia is active in the runtime log." >&2
    comparison_renderer_status=1
  fi
fi

tile_store_identity_status=0
primary_logcat="${primary_evidence}/espana-outdoor-map-logcat.txt"
if [[ ! -s "${primary_logcat}" ]] || ! grep -Fq "MAPBOX_TILE_STORE_USAGE requested=default effective=read_only" "${primary_logcat}"; then
  echo "ERROR: primary APK did not prove the default read-only TileStore mode." >&2
  tile_store_identity_status=1
fi
if [[ "${tile_store_disabled_run}" == "true" ]]; then
  diagnostic_logcat="${tile_store_disabled_evidence}/espana-outdoor-map-logcat.txt"
  if [[ ! -s "${diagnostic_logcat}" ]] || ! grep -Fq "MAPBOX_TILE_STORE_USAGE requested=disabled effective=disabled" "${diagnostic_logcat}"; then
    echo "ERROR: diagnostic APK did not prove TileStore is disabled at runtime." >&2
    tile_store_identity_status=1
  fi
fi

echo "MAPBOX_FLUTTER_RENDERER_AB style=${primary_style} primary_mode=hybrid-surface primary_renderer=impeller primary_status=${primary_status} comparison_run=${renderer_run} comparison_mode=hybrid-surface comparison_renderer=$([[ "${renderer_run}" == "true" ]] && echo skia || echo not-run) comparison_status=${renderer_status} renderer_identity_status=$((primary_renderer_status + comparison_renderer_status))"
echo "MAPBOX_TILE_STORE_USAGE_AB primary_mode=default primary_status=${primary_status} diagnostic_run=${tile_store_disabled_run} diagnostic_mode=disabled diagnostic_status=${tile_store_disabled_status} mode_identity_status=${tile_store_identity_status}"
if (( primary_status != 0 || renderer_status != 0 || tile_store_disabled_status != 0 || primary_renderer_status != 0 || comparison_renderer_status != 0 || tile_store_identity_status != 0 )); then
  exit 1
fi
