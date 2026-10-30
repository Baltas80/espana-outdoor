#!/usr/bin/env python3
"""Validate CI and mobile build configuration profiles."""

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
    "example.com", "example.org", "example.net", "localhost", "127.0.0.1", "::1",
}


def _fail(message: str) -> "NoReturn":
    print(f"BUILD PROFILE ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def _validate_https(name: str, raw: str) -> None:
    parsed = urlparse(raw)
    if parsed.scheme != "https" or not parsed.netloc:
        _fail(f"{name} must be a complete HTTPS URL.")
    host = (parsed.hostname or "").lower().rstrip(".")
    if host in PLACEHOLDER_HOSTS or host.endswith(".local") or host.startswith(("127.", "0.")):
        _fail(f"{name} points to a local or placeholder host: {host!r}.")
    if parsed.username or parsed.password:
        _fail(f"{name} must not embed credentials in the URL.")


def _check_endpoint_set(profile: str) -> None:
    for name in ANDROID_ENDPOINTS:
        value = os.environ.get(name, "").strip()
        if not value:
            _fail(f"Missing required {profile} endpoint: {name}.")
        _validate_https(name, value)


def check_ci() -> None:
    app_env = os.environ.get("APP_ENV", "")
    if app_env != "ci":
        _fail(f"CI profile requires APP_ENV=ci, got {app_env!r}")
    for name in (*ANDROID_ENDPOINTS, "MAPBOX_ACCESS_TOKEN"):
        if os.environ.get(name, "").strip():
            _fail(f"CI profile must not receive production variable {name}.")
    print("profile=ci")
    print("android_production_endpoints=absent")


def check_configured(profile: str) -> None:
    if os.environ.get("APP_ENV", "") != profile:
        _fail(f"{profile.title()} profile requires APP_ENV={profile}.")
    _check_endpoint_set(profile)
    print(f"profile={profile}")
    for name in ANDROID_ENDPOINTS:
        print(f"{name}=configured")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", choices=("ci", "staging", "production"), required=True)
    args = parser.parse_args()
    if args.profile == "ci":
        check_ci()
    else:
        check_configured(args.profile)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
