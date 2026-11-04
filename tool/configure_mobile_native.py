from __future__ import annotations

import argparse
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def configure_ios() -> None:
    """Apply iOS privacy and background-location declarations."""
    plist_path = ROOT / "ios" / "Runner" / "Info.plist"
    if not plist_path.exists():
        raise SystemExit(f"Missing iOS Info.plist: {plist_path}")

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


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Apply iOS privacy configuration; Android native sources are versioned and never generated."
    )
    parser.add_argument("--platform", choices=("ios",), default="ios")
    parser.parse_args()
    configure_ios()
    print("Mobile native configuration applied: ios.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())