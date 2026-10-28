#!/usr/bin/env python3
"""Validate CI and Android build configuration profiles.

The Android map uses MapLibre Flutter and a configured style URL. Offline map
rendering is not considered available until a separate implementation is
validated on an Android device.
"""

from __future__ import annotations

import argparse
import os
import sys
from urllib.parse import urlparse

ANDROID_ENDPOINTS = (
    "VALHALLA_BASE_URL",
    "SOURCE_GATEWAY_BASE_URL",
    "RESCUE_LINK_BASE_URL",
)

PLACEHOLDER_HOSTS = {
    "example.com",
    "example.org",
    "example.net",
    "localhost",
    "127.0.0.1",
    "::1",
}


def _fail(message: str) -> "NoReturn":
    print(f"BUILD PROFILE ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def _validate_https(name: str, raw: str) -> None:
    parsed = urlparse(raw)
    if parsed.scheme != "https" or not parsed.netloc:
        _fail(f"{name} must be a complete HTTPS URL.")

    host = parsed.hostname or ""
    lowered = host.lower().rstrip(".")
    if lowered in PLACEHOLDER_HOSTS or lowered.endswith(".local"):
        _fail(f"{name} points to a local/placeholder host: {host!r}.")

    if lowered.startswith("127.") or lowered.startswith("0."):
        _fail(f"{name} points to a local/private loopback-style host: {host!r}.")

    if parsed.username or parsed.password:
        _fail(f"{name} must not embed credentials in the URL.")


def _check_endpoint_set(profile: str) -> None:
    for name in ANDROID_ENDPOINTS:
        value = os.environ.get(name, "").strip()
        if not value:
            _fail(f"Missing required {profile} endpoint: {name}.")
        _validate_https(name, value)


def _check_map_style(profile: str) -> None:
    style_url = os.environ.get("MAP_STYLE_URL", "").strip()
    if not style_url:
        _fail(f"Missing required {profile} MapLibre style URL: MAP_STYLE_URL.")
    _validate_https("MAP_STYLE_URL", style_url)


def check_ci() -> None:
    app_env = os.environ.get("APP_ENV", "")
    if app_env != "ci":
        _fail(f"CI profile requires APP_ENV=ci, got {app_env!r}")

    for name in (*ANDROID_ENDPOINTS, "MAP_STYLE_URL"):
        if os.environ.get(name, "").strip():
            _fail(
                f"CI profile must not receive production variable {name}. "
                "Use the Android staging/release workflow instead."
            )

    print("profile=ci")
    print("android_production_endpoints=absent")


def check_staging() -> None:
    if os.environ.get("APP_ENV", "") != "staging":
        _fail(
            "Staging profile requires APP_ENV=staging, "
            f"got {os.environ.get('APP_ENV', '')!r}."
        )
    _check_endpoint_set("staging")
    _check_map_style("staging")

    print("profile=staging")
    for name in ANDROID_ENDPOINTS:
        print(f"{name}=configured")
    print("MAP_STYLE_URL=configured")


def check_production() -> None:
    if os.environ.get("APP_ENV", "") != "production":
        _fail(
            "Production profile requires APP_ENV=production, "
            f"got {os.environ.get('APP_ENV', '')!r}."
        )
    _check_endpoint_set("production")
    _check_map_style("production")

    print("profile=production")
    for name in ANDROID_ENDPOINTS:
        print(f"{name}=configured")
    print("MAP_STYLE_URL=configured")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", choices=("ci", "staging", "production"), required=True)
    args = parser.parse_args()

    if args.profile == "ci":
        check_ci()
    elif args.profile == "staging":
        check_staging()
    else:
        check_production()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
