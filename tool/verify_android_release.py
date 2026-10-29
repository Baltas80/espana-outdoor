#!/usr/bin/env python3
"""Verify that Android release archives contain required application assets."""

from __future__ import annotations

import argparse
from pathlib import Path
from zipfile import BadZipFile, ZipFile

REQUIRED_SUFFIXES = (
    "assets/flutter_assets/assets/brand/espana_outdoor_mark.svg",
    "assets/flutter_assets/assets/landscapes/picos_europa_land01.svg",
    "assets/flutter_assets/assets/backgrounds/bg_map.svg",
    "assets/flutter_assets/assets/visuals/hero_map.svg",
)


def _has_suffix(names: set[str], suffix: str) -> bool:
    return any(name == suffix or name.endswith("/" + suffix) for name in names)


def verify(path: Path) -> list[str]:
    try:
        with ZipFile(path) as archive:
            names = set(archive.namelist())
    except (BadZipFile, OSError) as exc:
        raise SystemExit(f"Invalid Android release archive: {path}: {exc}") from exc

    missing = [suffix for suffix in REQUIRED_SUFFIXES if not _has_suffix(names, suffix)]
    if missing:
        raise SystemExit("Android release asset verification failed; missing: " + ", ".join(missing))
    if not _has_suffix(names, "AndroidManifest.xml"):
        raise SystemExit("Android release asset verification failed; AndroidManifest.xml is missing.")
    return sorted(suffix for suffix in REQUIRED_SUFFIXES if _has_suffix(names, suffix))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--aab", type=Path)
    args = parser.parse_args()
    archives = [path for path in (args.apk, args.aab) if path is not None]
    if not archives:
        parser.error("Provide --apk and/or --aab.")
    for archive in archives:
        for asset in verify(archive):
            print(f"verified={archive} asset={asset}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
