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
        "Mapbox Navigation 3.34.2 / NDK27": 'com.mapbox.navigationcore:android-ndk27:3.34.2',
        "Mapbox Maps 11.34.2 / NDK27": 'com.mapbox.maps:android-ndk27:11.34.2',
        "Pinned Android NDK r27d": 'ndkVersion = "27.3.13750724"',
        "Application ID": 'applicationId = "com.espanaoutdoors.espana_outdoors"',
        "Android minSdk 24": "minSdk = 24",
    }
    for label, fragment in required_gradle.items():
        if fragment not in gradle:
            raise SystemExit(f"Android Gradle configuration is missing: {label}")

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

    main_dart = (ROOT / "lib" / "main.dart").read_text(encoding="utf-8")
    configure_index = main_dart.find("_navigationChannel.invokeMethod<void>('configure'")
    run_app_index = main_dart.find("runApp(")
    if configure_index < 0 or run_app_index < 0 or configure_index > run_app_index:
        raise SystemExit("The shared native TileStore must be configured before runApp().")

    pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    if "mapbox_maps_flutter: 3.34.1" not in pubspec:
        raise SystemExit("The Mapbox Flutter plugin must be pinned to 3.34.1.")
    if re.search(r"(?m)^  mapbox_maps_flutter_(mobile|platform_interface|web):", pubspec):
        raise SystemExit("Do not override endorsed Mapbox Flutter platform packages independently.")

    workflows = ("ci.yml", "staging-android.yml", "release-candidate.yml")
    for name in workflows:
        workflow_path = ROOT / ".github" / "workflows" / name
        workflow = workflow_path.read_text(encoding="utf-8")
        if "flutter create . --platforms=android" in workflow:
            raise SystemExit(f"{name} regenerates the committed Android project.")
        if "configure_mobile_native.py --platform android" in workflow:
            raise SystemExit(f"{name} mutates Android sources after checkout.")

    print("android_manifest=verified")
    print("android_main_activity=verified")
    print("android_application_id=com.espanaoutdoors.espana_outdoors")
    print("mapbox_flutter_sdk=3.34.1")
    print("mapbox_maps_android=11.34.2-ndk27")
    print("mapbox_navigation_android=3.34.2-ndk27")
    print("android_ndk=27.3.13750724")
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
