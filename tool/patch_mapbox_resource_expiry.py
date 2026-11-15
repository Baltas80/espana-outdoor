#!/usr/bin/env python3
"""Apply a narrow compatibility patch for Mapbox's no-expiry timestamp sentinel.

Mapbox Common can serialize an absent resource expiry as an int64 sentinel that
is outside Dart DateTime's supported range. The upstream Flutter platform
interface currently converts every non-null value directly to DateTime and
throws RangeError for this sentinel. This patch maps out-of-range timestamps to
null while preserving valid timestamps.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import url2pathname

_HELPER = """DateTime? _mapboxDateTimeFromMicroseconds(Object? value) {
  if (value is! int ||
      value < -8640000000000000000 ||
      value > 8640000000000000000) {
    return null;
  }
  return DateTime.fromMicrosecondsSinceEpoch(value);
}

"""

_OLD_MODIFIED = """modified: json['modified'] != null
          ? DateTime.fromMicrosecondsSinceEpoch(json['modified'] as int)
          : null,"""
_OLD_EXPIRES = """expires: json['expires'] != null
          ? DateTime.fromMicrosecondsSinceEpoch(json['expires'] as int)
          : null,"""
_NEW_MODIFIED = "modified: _mapboxDateTimeFromMicroseconds(json['modified']),"
_NEW_EXPIRES = "expires: _mapboxDateTimeFromMicroseconds(json['expires']),"


def patch_source(source: str) -> str:
    if "_mapboxDateTimeFromMicroseconds" in source:
        if _NEW_MODIFIED in source and _NEW_EXPIRES in source:
            return source
        raise ValueError("Mapbox expiry patch marker exists but parser does not match expected patched form")

    if source.count(_OLD_MODIFIED) != 1 or source.count(_OLD_EXPIRES) != 1:
        raise ValueError("Unexpected Mapbox ResourceResponse parser; refusing an unsafe partial patch")

    patched = source.replace(_OLD_MODIFIED, _NEW_MODIFIED, 1)
    patched = patched.replace(_OLD_EXPIRES, _NEW_EXPIRES, 1)
    anchor = "ResourceResponse _resourceResponseFromJson(Map<String, dynamic> json) =>"
    if patched.count(anchor) != 1:
        raise ValueError("Could not locate the expected ResourceResponse parser declaration")
    return patched.replace(anchor, _HELPER + anchor, 1)


def _package_root(package_config: Path) -> Path:
    data = json.loads(package_config.read_text(encoding="utf-8"))
    matches = [
        package
        for package in data.get("packages", [])
        if package.get("name") == "mapbox_maps_flutter_platform_interface"
    ]
    if len(matches) != 1:
        raise RuntimeError(
            "Expected one mapbox_maps_flutter_platform_interface package, "
            f"found {len(matches)}"
        )

    root_uri = matches[0]["rootUri"]
    parsed = urlparse(root_uri)
    if parsed.scheme == "file":
        return Path(url2pathname(parsed.path)).resolve()
    if parsed.scheme:
        raise RuntimeError(f"Unsupported Mapbox package root URI scheme: {parsed.scheme}")
    return (package_config.parent / root_uri).resolve()


def apply_patch(project_root: Path) -> bool:
    package_config = project_root / ".dart_tool" / "package_config.json"
    if not package_config.is_file():
        raise FileNotFoundError(
            f"Flutter package configuration not found: {package_config}; run flutter pub get first"
        )

    package_root = _package_root(package_config)
    package_manifest = package_root / "pubspec.yaml"
    if (
        not package_manifest.is_file()
        or "name: mapbox_maps_flutter_platform_interface"
        not in package_manifest.read_text(encoding="utf-8")
    ):
        raise RuntimeError(f"Resolved package is not the expected Mapbox platform interface: {package_root}")

    events_file = package_root / "lib" / "src" / "public" / "events.dart"
    if not events_file.is_file():
        raise FileNotFoundError(f"Mapbox events parser not found: {events_file}")

    original = events_file.read_text(encoding="utf-8")
    patched = patch_source(original)
    if patched == original:
        print("MAPBOX_RESOURCE_EXPIRY_PATCH already_applied=true")
        return False

    temporary = events_file.with_suffix(".dart.tmp")
    temporary.write_text(patched, encoding="utf-8", newline="\n")
    temporary.replace(events_file)
    print("MAPBOX_RESOURCE_EXPIRY_PATCH applied=true out_of_range_expiry=null")
    return True


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
    try:
        apply_patch(root)
    except Exception as error:
        print(f"::error::Mapbox resource expiry compatibility patch failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
