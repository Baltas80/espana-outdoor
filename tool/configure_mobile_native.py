from __future__ import annotations

import argparse
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def patch_android() -> None:
    manifest = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.exists():
        raise SystemExit(f"Missing generated Android manifest: {manifest}")

    permissions = [
        "android.permission.ACCESS_COARSE_LOCATION",
        "android.permission.ACCESS_FINE_LOCATION",
        "android.permission.ACCESS_BACKGROUND_LOCATION",
        "android.permission.FOREGROUND_SERVICE",
        "android.permission.FOREGROUND_SERVICE_LOCATION",
        "android.permission.INTERNET",
    ]

    text = manifest.read_text(encoding="utf-8")
    marker_end = text.find(">")
    if marker_end < 0:
        raise SystemExit("Invalid Android manifest.")

    insertion = []
    for permission in permissions:
        declaration = f'    <uses-permission android:name="{permission}" />'
        if permission not in text:
            insertion.append(declaration)

    if insertion:
        text = (
            text[: marker_end + 1]
            + "\n"
            + "\n".join(insertion)
            + text[marker_end + 1 :]
        )

    network_security = (
        ROOT / "android" / "app" / "src" / "main" / "res" / "xml"
        / "network_security_config.xml"
    )
    network_security.parent.mkdir(parents=True, exist_ok=True)
    network_security.write_text(
        '''<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
  <!-- MapLibre uses its configured style and sources.
       No remote cleartext traffic is permitted. -->
  <domain-config cleartextTrafficPermitted="true">
    <domain includeSubdomains="false">localhost</domain>
  </domain-config>
</network-security-config>
''',
        encoding="utf-8",
    )

    application_start = text.find("<application")
    if application_start < 0:
        raise SystemExit("Android manifest has no <application> element.")
    application_end = text.find(">", application_start)
    if application_end < 0:
        raise SystemExit("Invalid Android <application> element.")
    if "android:networkSecurityConfig=" not in text[application_start:application_end]:
        text = (
            text[:application_end]
            + ' android:networkSecurityConfig="@xml/network_security_config"'
            + text[application_end:]
        )

    # AppAuth owns its redirect receiver. Remove the callback activity left by
    # the retired OpenID Connect dependency so repeated native setup is safe.
    legacy_callback = re.compile(
        r'\s*<activity\b(?=[^>]*android:name="'
        r'io\.concerti\.openidconnect_android\.OpenIdConnectCallbackReceiverActivity"'
        r')[^>]*>.*?</activity>',
        re.DOTALL,
    )
    text = legacy_callback.sub("", text)

    manifest.write_text(text, encoding="utf-8")

    gradle_candidates = [
        ROOT / "android" / "app" / "build.gradle.kts",
        ROOT / "android" / "app" / "build.gradle",
    ]
    gradle_path = next((path for path in gradle_candidates if path.exists()), None)
    if gradle_path is None:
        raise SystemExit("Missing generated Android app Gradle file.")

    gradle = gradle_path.read_text(encoding="utf-8")
    if gradle_path.suffix == ".kts":
        gradle = gradle.replace("minSdk = flutter.minSdkVersion", "minSdk = 24")
        placeholder = (
            '        manifestPlaceholders["appAuthRedirectScheme"] = '
            '"com.espanaoutdoors"'
        )
    else:
        gradle = gradle.replace(
            "minSdkVersion flutter.minSdkVersion",
            "minSdkVersion 24",
        )
        placeholder = (
            '        manifestPlaceholders = '
            '[appAuthRedirectScheme: "com.espanaoutdoors"]'
        )

    if "appAuthRedirectScheme" not in gradle:
        default_config = "    defaultConfig {"
        if default_config not in gradle:
            raise SystemExit("Android Gradle file has no defaultConfig block.")
        gradle = gradle.replace(
            default_config,
            f"{default_config}\n{placeholder}",
            1,
        )

    gradle_path.write_text(gradle, encoding="utf-8")

    # Flutter 3.44+ may generate AGP 9 projects with built-in Kotlin enabled.
    # Mapbox's current Android plugin uses the Kotlin Gradle DSL and fails
    # with "Could not find method kotlin()" unless the legacy KGP path is used.
    gradle_properties = ROOT / "android" / "gradle.properties"
    if not gradle_properties.exists():
        raise SystemExit("Missing generated Android gradle.properties.")
    properties = gradle_properties.read_text(encoding="utf-8")
    property_line = "android.builtInKotlin=false"
    lines = [line for line in properties.splitlines() if not line.startswith("android.builtInKotlin=")]
    lines.append(property_line)
    gradle_properties.write_text("\\n".join(lines).rstrip() + "\\n", encoding="utf-8")


def patch_ios() -> None:
    plist_path = ROOT / "ios" / "Runner" / "Info.plist"
    if not plist_path.exists():
        raise SystemExit(f"Missing generated iOS Info.plist: {plist_path}")

    with plist_path.open("rb") as handle:
        plist = plistlib.load(handle)

    plist.setdefault(
        "NSLocationWhenInUseUsageDescription",
        "España Outdoor necesita tu ubicación para GPS, navegación, grabación de rutas y funciones de seguridad.",
    )
    plist.setdefault(
        "NSLocationAlwaysAndWhenInUseUsageDescription",
        "España Outdoor puede necesitar tu ubicación en segundo plano mientras grabas o navegas una ruta.",
    )

    modes = plist.setdefault("UIBackgroundModes", [])
    if "location" not in modes:
        modes.append("location")

    with plist_path.open("wb") as handle:
        plistlib.dump(plist, handle, fmt=plistlib.FMT_XML, sort_keys=False)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Apply platform-specific native configuration after flutter create."
    )
    parser.add_argument(
        "--platform",
        choices=("android", "ios", "all"),
        default="all",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    if args.platform in ("android", "all"):
        patch_android()
    if args.platform in ("ios", "all"):
        patch_ios()
    print(f"Mobile native configuration applied: {args.platform}.")
