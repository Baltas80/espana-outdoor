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
  <!-- Mapbox uses its configured style and sources.
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
        # AGP 9 has built-in Kotlin; Flutter's generated app template can still
        # apply the legacy Kotlin Android plugin, which AGP 9 rejects.
        gradle = re.sub(
            r"""(?m)^\s*id\(["'](?:org\.jetbrains\.kotlin\.android|kotlin-android)["']\)\s*\n""",
            "",
            gradle,
        )
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

    if "com.mapbox.navigationcore:android-ndk27:3.33.0" not in gradle:
        dependency = '    implementation("com.mapbox.navigationcore:android-ndk27:3.33.0")'
        dependency_match = re.search(r"(?m)^dependencies\s*\{", gradle)
        if dependency_match:
            insert_at = dependency_match.end()
            gradle = gradle[:insert_at] + "\n" + dependency + gradle[insert_at:]
        else:
            gradle += "\ndependencies {\n" + dependency + "\n}\n"
    gradle_path.write_text(gradle, encoding="utf-8")

    # Keep Maven repositories at project level. Flutter's Gradle plugin adds
    # the Flutter engine Maven repository to Android subprojects; using
    # PREFER_SETTINGS would silently ignore it and break Flutter embedding.
    root_gradle_candidates = [
        ROOT / "android" / "build.gradle.kts",
        ROOT / "android" / "build.gradle",
    ]
    root_gradle_path = next((path for path in root_gradle_candidates if path.exists()), None)
    if root_gradle_path is None:
        raise SystemExit("Missing generated Android root Gradle file.")
    root_gradle = root_gradle_path.read_text(encoding="utf-8")
    mapbox_repository = (
        '        maven {\n'
        '            url = uri("https://api.mapbox.com/downloads/v2/releases/maven")\n'
        '            credentials {\n'
        '                username = "mapbox"\n'
        '                password = System.getenv("MAPBOX_DOWNLOADS_TOKEN") ?: ""\n'
        '            }\n'
        '            authentication {\n'
        '                create<org.gradle.authentication.http.BasicAuthentication>("basic")\n'
        '            }\n'
        '        }'
    )
    if "api.mapbox.com/downloads/v2/releases/maven" not in root_gradle:
        if root_gradle_path.suffix == ".kts":
            if re.search(r"(?m)^\s*mavenCentral\(\)\s*$", root_gradle):
                root_gradle = re.sub(
                    r"(?m)^(\s*)mavenCentral\(\)\s*$",
                    lambda match: match.group(0) + "\n" + mapbox_repository,
                    root_gradle,
                    count=1,
                )
            else:
                root_gradle = (
                    "allprojects {\n"
                    "    repositories {\n"
                    "        google()\n"
                    "        mavenCentral()\n"
                    + mapbox_repository + "\n"
                    "    }\n"
                    "}\n\n"
                    + root_gradle
                )
        else:
            groovy_repository = (
                '        maven {\n'
                '            url "https://api.mapbox.com/downloads/v2/releases/maven"\n'
                '            credentials { username = "mapbox"; password = System.getenv("MAPBOX_DOWNLOADS_TOKEN") ?: "" }\n'
                '            authentication { basic(org.gradle.authentication.http.BasicAuthentication) }\n'
                '        }'
            )
            if re.search(r"(?m)^\s*mavenCentral\(\)\s*$", root_gradle):
                root_gradle = re.sub(
                    r"(?m)^(\s*)mavenCentral\(\)\s*$",
                    lambda match: match.group(0) + "\n" + groovy_repository,
                    root_gradle,
                    count=1,
                )
            else:
                raise SystemExit("Could not add Mapbox Maven repository to generated root Gradle file.")
    root_gradle_path.write_text(root_gradle, encoding="utf-8")

    # Flutter regenerates MainActivity.kt in CI; restore the native Mapbox bridge.
    kotlin_root = ROOT / "android" / "app" / "src" / "main" / "kotlin"
    main_activities = list(kotlin_root.rglob("MainActivity.kt")) if kotlin_root.exists() else []
    if not main_activities:
        raise SystemExit("Missing generated Android MainActivity.kt.")
    activity_path = main_activities[0]
    activity_source = activity_path.read_text(encoding="utf-8")
    package_match = re.search(r"(?m)^package\s+([A-Za-z0-9_.]+)", activity_source)
    if package_match is None:
        raise SystemExit("Could not determine the generated MainActivity package.")
    activity_template = """package __PACKAGE__

import com.espana.outdoors.navigation.MapboxNavigationBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var navigationBridge: MapboxNavigationBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        navigationBridge = MapboxNavigationBridge(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.espanaoutdoors/navigation"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    val token = call.argument<String>("accessToken")
                    if (token.isNullOrBlank()) {
                        result.error("MISSING_TOKEN", "Mapbox access token is required.", null)
                    } else {
                        runCatching { navigationBridge.configure(token) }
                            .onSuccess { result.success(null) }
                            .onFailure {
                                result.error("NAVIGATION_INIT_FAILED", it.message, null)
                            }
                    }
                }
                "requestRoute" -> navigationBridge.requestRoute(call.arguments, result)
                "downloadOfflineRegion" -> navigationBridge.downloadOfflineRegion(call.arguments, result)
                "hasOfflineRegion" -> navigationBridge.hasOfflineRegion(call.arguments, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (::navigationBridge.isInitialized) navigationBridge.destroy()
        super.onDestroy()
    }
}
"""
    activity_path.write_text(
        activity_template.replace("__PACKAGE__", package_match.group(1)),
        encoding="utf-8",
    )

    # AGP 9 exposes the Kotlin DSL to plugins through built-in Kotlin.
    # Mapbox's Android module configures the kotlin {} extension; disabling
    # built-in Kotlin makes that extension unavailable and breaks the build.
    # Flutter 3.47 supports opting in, so keep it enabled for this AGP 9 project.
    gradle_properties = ROOT / "android" / "gradle.properties"
    if not gradle_properties.exists():
        raise SystemExit("Missing generated Android gradle.properties.")
    properties = gradle_properties.read_text(encoding="utf-8")
    property_line = "android.builtInKotlin=true"
    lines = [line for line in properties.splitlines() if not line.startswith("android.builtInKotlin=")]
    lines.append(property_line)
    gradle_properties.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


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
