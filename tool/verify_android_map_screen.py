#!/usr/bin/env python3
"""Reject screenshots unless UIAutomator proves the real Mapbox map page is open."""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

REQUIRED_CONTROLS = ("Mapa cartográfico",)
HOME_MARKERS = ("Explora España",)
ANR_MARKERS = ("isn't responding", "is not responding")


def _xml_root(raw: str) -> ET.Element:
    start = raw.find("<?xml")
    if start < 0:
        start = raw.find("<hierarchy")
    end = raw.find("</hierarchy>", start)
    if start < 0 or end < 0:
        raise ValueError("uiautomator_hierarchy_missing")
    return ET.fromstring(raw[start : end + len("</hierarchy>")])


def verify_map_page(raw: str, expected_package: str) -> tuple[bool, str]:
    try:
        hierarchy = _xml_root(raw)
    except (ET.ParseError, ValueError):
        return False, "invalid_hierarchy"

    if hierarchy.tag != "hierarchy":
        return False, "unexpected_root"

    top = next((node for node in hierarchy if node.tag == "node"), None)
    if top is None:
        return False, "empty_hierarchy"

    actual_package = (top.attrib.get("package") or "").strip()
    if actual_package != expected_package:
        return False, f"window_owned_by_{actual_package or 'unknown'}"

    labels: list[str] = []
    for node in hierarchy.iter("node"):
        text = (node.attrib.get("text") or "").strip()
        description = (node.attrib.get("content-desc") or "").strip()
        if text:
            labels.append(text)
        if description:
            labels.append(description)

    joined = "\n".join(labels)
    if any(marker in joined for marker in ANR_MARKERS):
        return False, "system_anr_dialog_visible"
    if any(marker in joined for marker in HOME_MARKERS):
        return False, "home_page_still_visible"

    missing = [label for label in REQUIRED_CONTROLS if label not in labels]
    if missing:
        return False, "missing_map_controls:" + ",".join(missing)

    return True, "map_page_confirmed"


def _self_test() -> None:
    package = "com.espanaoutdoors.espana_outdoors.iconspreview"
    valid = (
        '<hierarchy rotation="0"><node package="' + package + '">'
        '<node text="Mapa" /><node content-desc="Mapa cartográfico" />'
        "</node></hierarchy>"
    )
    home = (
        '<hierarchy rotation="0"><node package="' + package + '">'
        '<node content-desc="Explora España" /><node content-desc="Mapa" />'
        "</node></hierarchy>"
    )
    system_dialog = (
        '<hierarchy rotation="0"><node package="android">'
        '<node text="com.google.android.googlesdksetup isn\'t responding" />'
        "</node></hierarchy>"
    )
    assert verify_map_page(valid, package) == (True, "map_page_confirmed")
    assert verify_map_page(home, package) == (False, "home_page_still_visible")
    assert verify_map_page(system_dialog, package)[0] is False
    assert verify_map_page(system_dialog, package)[1].startswith("window_owned_by_android")
    print("ANDROID_MAP_PAGE_VERIFIER_SELF_TEST passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("hierarchy", nargs="?", type=Path)
    parser.add_argument("--package")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        _self_test()
        return 0
    if args.hierarchy is None or not args.package:
        parser.error("provide a UIAutomator hierarchy and --package")

    try:
        raw = args.hierarchy.read_text(encoding="utf-8", errors="replace")
    except OSError as error:
        print(f"MAPBOX_MAP_PAGE_REJECTED reason=hierarchy_unreadable type={type(error).__name__}", file=sys.stderr)
        return 1

    accepted, reason = verify_map_page(raw, args.package)
    if not accepted:
        print(f"MAPBOX_MAP_PAGE_REJECTED reason={reason}", file=sys.stderr)
        return 1
    print(
        "MAPBOX_MAP_PAGE_VISIBLE "
        f"package={args.package} controls={','.join(REQUIRED_CONTROLS)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
