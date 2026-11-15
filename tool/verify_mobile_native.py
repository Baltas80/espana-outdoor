#!/usr/bin/env python3
"""Verify committed Android/iOS native configuration before mobile builds."""

from __future__ import annotations

import argparse
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

ANDROID_PERMISSIONS = {
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_BACKGROUND_LOCATION",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_LOCATION",
    "android.permission.INTERNET",
}


def verify_android() -> None:
    manifest = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.is_file():
        raise SystemExit(f"Missing committed Android manifest: {manifest}")
    manifest_text = manifest.read_text(encoding="utf-8")
    missing = sorted(
        permission
        for permission in ANDROID_PERMISSIONS
        if f'android:name="{permission}"' not in manifest_text
    )
    if missing:
        raise SystemExit("Android manifest is missing: " + ", ".join(missing))
    if "OpenIdConnectCallbackReceiverActivity" in manifest_text:
        raise SystemExit("Retired OpenID Connect callback activity remains in AndroidManifest.xml.")

    gradle_path = ROOT / "android" / "app" / "build.gradle.kts"
    if not gradle_path.is_file():
        raise SystemExit(f"Missing committed Android Gradle file: {gradle_path}")
    gradle = gradle_path.read_text(encoding="utf-8")
    required_gradle = {
        "Mapbox Navigation 3.35.0 / NDK27": 'com.mapbox.navigationcore:android-ndk27:3.35.0',
        "Mapbox Maps 11.35.0 / NDK27": 'com.mapbox.maps:android-ndk27:11.35.0',
        "Pinned Android NDK 28.2": 'ndkVersion = "28.2.13676358"',
        "Application ID default": '?: "com.espanaoutdoors.espana_outdoors"',
        "Android minSdk 24": "minSdk = 24",
    }
    required_gradle["Mapbox Common 24.35.0 / NDK27"] = 'com.mapbox.common:common-ndk27:24.35.0'
    for label, fragment in required_gradle.items():
        if fragment not in gradle:
            raise SystemExit(f"Android Gradle configuration is missing: {label}")
    if "applicationId = applicationIdValue" not in gradle or "ANDROID_APPLICATION_ID" not in gradle:
        raise SystemExit("Android staging package ID must be configurable without changing the production default.")

    root_gradle_path = ROOT / "android" / "build.gradle.kts"
    root_gradle = root_gradle_path.read_text(encoding="utf-8")
    for fragment in (
        "https://api.mapbox.com/downloads/v2/releases/maven",
        "MAPBOX_DOWNLOADS_TOKEN",
        'username = "mapbox"',
    ):
        if fragment not in root_gradle:
            raise SystemExit("Android root Gradle is missing Mapbox Downloads Maven authentication.")

    release_signing_markers = (
        "ANDROID_RELEASE_STORE_FILE",
        "ANDROID_RELEASE_STORE_PASSWORD",
        "ANDROID_RELEASE_KEY_ALIAS",
        "ANDROID_RELEASE_KEY_PASSWORD",
        "releaseSigningConfigured",
        'System.getenv("APP_ENV") == "production"',
    )
    missing_signing = [marker for marker in release_signing_markers if marker not in gradle]
    if missing_signing or "signingConfig = if (releaseSigningConfigured)" not in gradle:
        raise SystemExit(
            "Committed Android Gradle must fail closed for production and use a dedicated release keystore. Missing: "
            + ", ".join(missing_signing or ["release signing selector"])
        )

    if re.search(r'''(?m)^\s*id\(["']org\.jetbrains\.kotlin\.android["']\)''', gradle):
        raise SystemExit("Legacy Kotlin Android plugin must not be applied with AGP 9 built-in Kotlin.")
    properties_path = ROOT / "android" / "gradle.properties"
    properties = properties_path.read_text(encoding="utf-8")
    if not re.search(r"(?m)^android\.builtInKotlin=true\s*$", properties):
        raise SystemExit("AGP 9 built-in Kotlin must be enabled in committed gradle.properties.")

    namespace_match = re.search(r'namespace = "([A-Za-z0-9_.]+)"', gradle)
    if namespace_match is None:
        raise SystemExit("Cannot determine the Android namespace.")
    namespace = namespace_match.group(1)
    kotlin_root = ROOT / "android" / "app" / "src" / "main" / "kotlin"
    activities = list(kotlin_root.rglob("MainActivity.kt"))
    expected_activity = kotlin_root.joinpath(*namespace.split("."), "MainActivity.kt")
    if len(activities) != 1 or activities[0] != expected_activity:
        raise SystemExit(
            "Expected exactly one committed MainActivity at the namespace path; "
            f"found {[str(path.relative_to(ROOT)) for path in activities]}"
        )
    activity_text = expected_activity.read_text(encoding="utf-8")
    if "com.espanaoutdoors/navigation" not in activity_text or '"configure" ->' not in activity_text:
        raise SystemExit("MainActivity is missing the Mapbox Navigation startup channel.")

    bridge_path = kotlin_root / "com" / "espana" / "outdoors" / "navigation" / "MapboxNavigationBridge.kt"
    if not bridge_path.is_file():
        raise SystemExit("MapboxNavigationBridge.kt is missing.")
    bridge = bridge_path.read_text(encoding="utf-8")
    for label, fragment in {
        "persistent no-backup TileStore": "context.noBackupFilesDir",
        "single process TileStore": "processTileStore",
        "Maps SDK shared TileStore": "MapboxMapsOptions.tileStore = store",
        "Navigation SDK shared TileStore": ".tileStore(store)",
        "Maps read/update mode": "TileStoreUsageMode.READ_AND_UPDATE",
        "global Mapbox runtime token": "MapboxOptions.accessToken = accessToken",
        "strict online/offline source": "RouterOrigin.ONLINE",
        "synchronous offline metadata persistence": ".commit()",
    }.items():
        if fragment not in bridge:
            raise SystemExit(f"Native Mapbox bridge is missing: {label}")

    token_index = bridge.find("MapboxOptions.accessToken = accessToken")
    store_init_index = bridge.find("getOrCreateProcessTileStore(appContext)")
    if token_index < 0 or store_init_index < 0 or token_index > store_init_index:
        raise SystemExit("Set the global Mapbox access token before creating the shared TileStore.")
    if "TileStoreOptions.MAPBOX_ACCESS_TOKEN" in bridge:
        raise SystemExit("TileStoreOptions.MAPBOX_ACCESS_TOKEN was removed from Maps SDK v11.")
    for label, fragment in {
        "walking-only offline routing tiles": '.tilesProfile("walking")',
        "shared Maps and Navigation region descriptors": "descriptors(listOf(mapsDescriptor, navigationDescriptor))",
        "offline router origin": "RouterOrigin.OFFLINE",
    }.items():
        if fragment not in bridge:
            raise SystemExit(f"Native Mapbox bridge is missing: {label}")
    if '"message" to failure.message' in bridge:
        raise SystemExit("Native Mapbox failure messages must not expose request URLs or tokens.")

    main_dart = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")
    configure_match = re.search(
        r"_navigationChannel\s*\.\s*invokeMethod<void>\(\s*['\"]configure['\"]",
        main_dart,
        re.DOTALL,
    )
    run_app_match = re.search(r"\brunApp\s*\(", main_dart)
    if (
        configure_match is None
        or run_app_match is None
        or configure_match.start() > run_app_match.start()
    ):
        raise SystemExit("The shared native TileStore must be configured before runApp().")

    offline_page = (ROOT / "lib" / "features" / "offline" / "offline_page.dart").read_text(encoding="utf-8")
    if "downloadOfflineRegion" not in offline_page or "hasOfflineRegion" not in offline_page:
        raise SystemExit("OfflinePage must use the native shared TileStore bridge.")
    if "TileStore.createDefault" in offline_page or "OfflineManager.create" in offline_page:
        raise SystemExit("OfflinePage must not create a second, separate Mapbox TileStore.")

    routing_provider = (ROOT / "lib" / "core" / "routing" / "routing_provider.dart").read_text(encoding="utf-8")
    composite = (ROOT / "lib" / "infrastructure" / "routing" / "composite_routing_service.dart").read_text(encoding="utf-8")
    if "CompositeRoutingService" not in routing_provider or "MapboxNavigationRoutingService" not in routing_provider:
        raise SystemExit("Android routing provider must use the composite Mapbox/Valhalla selector.")
    if "walking ? (mapbox ?? valhalla) : valhalla" not in composite or "final service = valhalla" not in composite:
        raise SystemExit("Composite routing must preserve Valhalla for bicycle profiles and GPX matching.")

    viewport = ROOT / "lib" / "features" / "map" / "mapbox_map_viewport.dart"
    viewport_text = viewport.read_text(encoding="utf-8")
    required_viewport_diagnostics = (
        "onMapLoadedListener",
        "onRenderFrameFinishedListener",
        "onResourceRequestListener",
        "MAPBOX_MAP_PARTIAL_FRAME",
        "MAPBOX_RESOURCE_FAILURE",
        "MAPBOX_MAP_LOADED",
        "MAPBOX_MAP_FULL_FRAME",
        "MAPBOX_MAP_IDLE",
    )
    for marker in required_viewport_diagnostics:
        if marker not in viewport_text:
            raise SystemExit(
                f"Mapbox viewport is missing bounded render diagnostics: {marker}"
            )

    integration_test = ROOT / "integration_test" / "mapbox_android_live_route_test.dart"
    if not integration_test.is_file():
        raise SystemExit("The Android online/offline Mapbox integration test is missing.")
    integration_text = integration_test.read_text(encoding="utf-8")
    required_integration_evidence = (
        "RouterOrigin.OFFLINE",
        "MAPBOX_ROUTE_VALIDATION source=offline",
        "onStyleLoadedListener",
        "onRenderFrameFinishedListener",
        "RenderMode.FULL",
        "MAPBOX_OFFLINE_MAP_DIAGNOSTICS",
        "MAPBOX_OFFLINE_MAP_RENDERED",
        "unique_colors",
        "opaque_ratio",
        "entropy_bits",
        "dominant_ratio",
        "MAPBOX_OFFLINE_RENDER_GATE version=2",
        "greaterThan(24)",
        "greaterThan(1.2)",
        "lessThan(0.85)",
    )
    for marker in required_integration_evidence:
        if marker not in integration_text:
            raise SystemExit(
                f"Android offline integration test is missing evidence marker: {marker}"
            )

    pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    if "mapbox_maps_flutter: 3.34.1" not in pubspec:
        raise SystemExit("The Mapbox Flutter plugin must be pinned to 3.34.1.")
    if re.search(r"(?m)^  mapbox_maps_flutter_(mobile|platform_interface|web):", pubspec):
        raise SystemExit("Do not override endorsed Mapbox Flutter platform packages independently.")

    build_profile = (ROOT / "tool" / "verify_build_profile.py").read_text(encoding="utf-8")
    if '"VALHALLA_BASE_URL"' not in build_profile:
        raise SystemExit("Valhalla must remain configured for BTT, cycle touring and GPX matching.")

    workflows = ("ci.yml", "staging-android.yml", "release-candidate.yml")
    for name in workflows:
        workflow_path = ROOT / ".github" / "workflows" / name
        workflow = workflow_path.read_text(encoding="utf-8")
        if "flutter create . --platforms=android" in workflow:
            raise SystemExit(f"{name} regenerates the committed Android project.")
        if "configure_mobile_native.py --platform android" in workflow:
            raise SystemExit(f"{name} mutates Android sources after checkout.")
        if name in ("staging-android.yml", "release-candidate.yml"):
            if "MAPBOX_DOWNLOADS_TOKEN" not in workflow or "VALHALLA_BASE_URL" not in workflow:
                raise SystemExit(f"{name} must preserve Mapbox Maven credentials and Valhalla routing configuration.")
        if name == "staging-android.yml":
            for marker in ("timeout-minutes: 60", "timeout-minutes: 30", "apk_sha256=", "application_id=", "version_code=", "source_commit="):
                if marker not in workflow:
                    raise SystemExit(f"Android staging is missing bounded/reproducible artifact validation: {marker}")

    staging_script = (ROOT / "tool" / "staging_android_route_integration.sh").read_text(encoding="utf-8")
    for marker in (
        "MAPBOX_OFFLINE_MAP_RENDERED",
        "TEST_PACKAGE_NAME",
        "namespace[[:space:]]*=",
        "am force-stop",
        "--no-pub",
        "timeout --signal=TERM",
        "ROUTE_PHASE_START",
        "<REDACTED>",
    ):
        if marker not in staging_script:
            raise SystemExit(f"Android staging route harness is missing: {marker}")

    map_viewport = (ROOT / "lib" / "features" / "map" / "mapbox_map_viewport.dart").read_text(encoding="utf-8")
    for marker in ("MAPBOX_MAP_STYLE_LOADED", "MAPBOX_MAP_FULL_FRAME", "MAPBOX_MAP_IDLE", "onMapLoadErrorListener"):
        if marker not in map_viewport:
            raise SystemExit(f"Mapbox viewport is missing render diagnostics: {marker}")
    smoke_script = (ROOT / "tool" / "smoke_android_map.sh").read_text(encoding="utf-8")
    for marker in ("MAPBOX_MAP_STYLE_LOADED", "MAPBOX_MAP_FULL_FRAME", "MAPBOX_MAP_IDLE", "<REDACTED>"):
        if marker not in smoke_script:
            raise SystemExit(f"Android map smoke does not wait for: {marker}")
    oppo_script = (ROOT / "tool" / "test_mapbox_oppo_routes.ps1").read_text(encoding="utf-8")
    for marker in ("RebootAfterOffline", "--enforce-lockfile", "patch_mapbox_resource_expiry.py", "verify_mapbox_lock.py"):
        if marker not in oppo_script:
            raise SystemExit(f"The physical integration script is missing CI parity marker: {marker}")
    release_device_script = ROOT / "tool" / "verify_install_android_apk.ps1"
    if not release_device_script.is_file():
        raise SystemExit("The exact release APK device validation script is missing.")
    release_device_text = release_device_script.read_text(encoding="utf-8")
    for marker in ("apk_sha256", "application_id", "version_code", "OfflineSmoke", "RebootAfterInstall", "install"):
        if marker not in release_device_text:
            raise SystemExit(f"The release APK device validation script is missing: {marker}")

    print("android_manifest=verified")
    print("android_main_activity=verified")
    print("android_application_id=com.espanaoutdoors.espana_outdoors")
    print("mapbox_flutter_sdk=3.34.1")
    print("mapbox_maps_android=11.35.0-ndk27")
    print("mapbox_navigation_android=3.35.0-ndk27")
    print("mapbox_common=24.35.0-ndk27")
    print("android_ndk=28.2.13676358")
    print("shared_persistent_tilestore=verified")
    print("android_ci_uses_committed_sources=verified")


def verify_ios() -> None:
    plist_path = ROOT / "ios" / "Runner" / "Info.plist"
    if not plist_path.exists():
        raise SystemExit(f"Missing iOS Info.plist: {plist_path}")
    with plist_path.open("rb") as handle:
        plist = plistlib.load(handle)
    required = {
        "NSLocationWhenInUseUsageDescription",
        "NSLocationAlwaysAndWhenInUseUsageDescription",
    }
    missing = sorted(required - plist.keys())
    if missing:
        raise SystemExit("iOS Info.plist is missing: " + ", ".join(missing))
    if "location" not in plist.get("UIBackgroundModes", []):
        raise SystemExit("iOS background location mode is missing.")
    print("ios_info_plist=verified")
    print("ios_location_usage_descriptions=verified")
    print("ios_background_location=verified")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=("android", "ios"), required=True)
    args = parser.parse_args()
    if args.platform == "android":
        verify_android()
    else:
        verify_ios()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
