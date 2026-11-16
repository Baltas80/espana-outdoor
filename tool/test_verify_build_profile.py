#!/usr/bin/env python3
"""Regression tests for mobile build-profile endpoint requirements."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).with_name("verify_build_profile.py")
ENDPOINTS = (
    "VALHALLA_BASE_URL",
    "SOURCE_GATEWAY_BASE_URL",
    "COMMUNITY_API_BASE_URL",
    "RESCUE_LINK_BASE_URL",
)
TEST_ENDPOINTS = {
    name: f"https://{name.lower().replace('_base_url', '').replace('_', '-')}.example.test"
    for name in ENDPOINTS
}


def clean_environment() -> dict[str, str]:
    env = os.environ.copy()
    for name in (*ENDPOINTS, "MAPBOX_ACCESS_TOKEN"):
        env.pop(name, None)
    return env


def run(profile: str, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--profile", profile],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


def expect(profile: str, env: dict[str, str], success: bool, label: str) -> None:
    result = run(profile, env)
    if (result.returncode == 0) != success:
        raise AssertionError(
            f"{label}: expected success={success}, got {result.returncode}. "
            f"stdout={result.stdout!r}; stderr={result.stderr!r}"
        )
    print(f"PASS {label}")


def configured_environment(profile: str) -> dict[str, str]:
    env = clean_environment()
    env["APP_ENV"] = profile
    env.update(TEST_ENDPOINTS)
    return env


def main() -> int:
    ci = clean_environment()
    ci["APP_ENV"] = "ci"
    expect("ci", ci, True, "CI allows an endpoint-free isolated build")

    ci_with_community = dict(ci)
    ci_with_community["COMMUNITY_API_BASE_URL"] = TEST_ENDPOINTS["COMMUNITY_API_BASE_URL"]
    expect("ci", ci_with_community, False, "CI rejects production community API configuration")

    staging = configured_environment("staging")
    expect("staging", staging, True, "staging requires all four API endpoints")

    staging_without_community = dict(staging)
    staging_without_community.pop("COMMUNITY_API_BASE_URL")
    expect(
        "staging",
        staging_without_community,
        False,
        "staging rejects a missing community API endpoint",
    )

    staging_http_community = dict(staging)
    staging_http_community["COMMUNITY_API_BASE_URL"] = "http://api.example.test"
    expect(
        "staging",
        staging_http_community,
        False,
        "staging rejects a non-HTTPS community API endpoint",
    )

    production = configured_environment("production")
    expect("production", production, True, "production requires all four API endpoints")

    production_without_community = dict(production)
    production_without_community.pop("COMMUNITY_API_BASE_URL")
    expect(
        "production",
        production_without_community,
        False,
        "production rejects a missing community API endpoint",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
