#!/usr/bin/env python3
"""Verify generated Android/iOS native configuration before mobile builds."""

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
}


def verify_android() -> None:
    manifest = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.exists():
        raise SystemExit(f"Missing Android manifest: {manifest}")

    text = manifest.read_text(encoding="utf-8")
    missing = [
        permission
        for permission in sorted(ANDROID_PERMISSIONS)
        if f'android:name="{permission}"' not in text
    ]
    if missing:
        raise SystemExit(
            "Android manifest is missing required permissions: "
            + ", ".join(missing)
        )

    legacy_callback = "io.concerti.openidconnect_android.OpenIdConnectCallbackReceiverActivity"
    if legacy_callback in text:
        raise SystemExit(
            "Legacy OpenIdConnect callback activity is present after migration "
            "to flutter_appauth."
        )

    gradle_candidates = (
        ROOT / "android" / "app" / "build.gradle.kts",
        ROOT / "android" / "app" / "build.gradle",
    )
    gradle = next((path for path in gradle_candidates if path.exists()), None)
    if gradle is None:
        raise SystemExit("Missing Android app Gradle file.")

    content = gradle.read_text(encoding="utf-8")
    gradle_properties = ROOT / "android" / "gradle.properties"
    if not gradle_properties.exists():
        raise SystemExit("Missing generated Android gradle.properties.")
    properties = gradle_properties.read_text(encoding="utf-8")
    if not re.search(r"(?m)^android\.builtInKotlin=false\s*$", properties):
        raise SystemExit("Android built-in Kotlin must be disabled for Mapbox Gradle compatibility.")
    if not re.search(r"minSdk(?:Version\s+|\s*=\s*)24\b", content):
        raise SystemExit("Android minSdk 24 was not enforced by native configuration.")

    kotlin_placeholder = re.search(
        r'manifestPlaceholders\s*\[\s*"appAuthRedirectScheme"\s*\]\s*='
        r'\s*"com\.espanaoutdoors"',
        content,
    )
    groovy_placeholder = re.search(
        r'manifestPlaceholders\s*=\s*\['
        r'[^]]*appAuthRedirectScheme\s*:\s*"com\.espanaoutdoors"',
        content,
    )
    if not (kotlin_placeholder or groovy_placeholder):
        raise SystemExit(
            "Android appAuthRedirectScheme manifest placeholder was not "
            "configured as com.espanaoutdoors."
        )


    print("android_manifest=verified")
    print("android_permissions=verified")
    print("android_min_sdk=24")
    print("android_auth_redirect_scheme=verified")
    print("android_no_legacy_oidc_callback=verified")


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
        raise SystemExit(
            "iOS Info.plist is missing location usage descriptions: "
            + ", ".join(missing)
        )

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
