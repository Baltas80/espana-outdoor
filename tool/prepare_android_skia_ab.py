#!/usr/bin/env python3
"""Apply a release-only Impeller opt-out to a disposable A/B build manifest."""
from __future__ import annotations
import argparse
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID_NS = "http://schemas.android.com/apk/res/android"
IMPELLER_META_NAME = "io.flutter.embedding.android.EnableImpeller"
ANDROID_NAME = f"{{{ANDROID_NS}}}name"
ANDROID_VALUE = f"{{{ANDROID_NS}}}value"

def disable_impeller(manifest_path: Path) -> None:
    if not manifest_path.is_file():
        raise SystemExit(f"Android manifest does not exist: {manifest_path}")
    ET.register_namespace("android", ANDROID_NS)
    try:
        tree = ET.parse(manifest_path)
    except ET.ParseError as error:
        raise SystemExit(f"Android manifest is not valid XML: {error}") from error
    root = tree.getroot()
    application = root.find("application")
    if application is None:
        raise SystemExit("Android manifest has no application element.")
    matches = [node for node in application.findall("meta-data")
               if node.get(ANDROID_NAME) == IMPELLER_META_NAME]
    if len(matches) > 1:
        raise SystemExit("Android manifest contains duplicate EnableImpeller metadata.")
    metadata = matches[0] if matches else ET.SubElement(application, "meta-data")
    metadata.set(ANDROID_NAME, IMPELLER_META_NAME)
    metadata.set(ANDROID_VALUE, "false")
    tree.write(manifest_path, encoding="utf-8", xml_declaration=True)
    verified_root = ET.parse(manifest_path).getroot()
    verified_app = verified_root.find("application")
    if verified_app is None:
        raise SystemExit("Android manifest lost its application element.")
    verified = [node for node in verified_app.findall("meta-data")
                if node.get(ANDROID_NAME) == IMPELLER_META_NAME]
    if len(verified) != 1 or verified[0].get(ANDROID_VALUE) != "false":
        raise SystemExit("Could not verify EnableImpeller=false in the comparison manifest.")

def self_test() -> None:
    sample = f"""<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="{ANDROID_NS}">
  <application android:label="sample">
    <meta-data android:name="sample.existing" android:value="true" />
  </application>
</manifest>
"""
    with tempfile.TemporaryDirectory(prefix="android-skia-ab-") as directory:
        manifest = Path(directory) / "AndroidManifest.xml"
        manifest.write_text(sample, encoding="utf-8")
        disable_impeller(manifest)
        disable_impeller(manifest)
        root = ET.parse(manifest).getroot()
        app = root.find("application")
        assert app is not None
        matches = [node for node in app.findall("meta-data")
                   if node.get(ANDROID_NAME) == IMPELLER_META_NAME]
        assert len(matches) == 1 and matches[0].get(ANDROID_VALUE) == "false"
    print("android_skia_ab_manifest_self_test=passed")

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", nargs="?", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if args.manifest is None:
        parser.error("manifest is required unless --self-test is used")
    disable_impeller(args.manifest)
    print(f"android_skia_ab_manifest={args.manifest} impeller=false")

if __name__ == "__main__":
    main()
