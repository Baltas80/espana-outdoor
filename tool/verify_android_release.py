#!/usr/bin/env python3
"""Verify Android release archives and, when requested, their signing identity."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import os
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
        raise SystemExit(
            "Android release asset verification failed; missing: "
            + ", ".join(missing)
        )
    if not _has_suffix(names, "AndroidManifest.xml"):
        raise SystemExit(
            "Android release asset verification failed; AndroidManifest.xml is missing."
        )
    return sorted(suffix for suffix in REQUIRED_SUFFIXES if _has_suffix(names, suffix))


def _normalize_fingerprint(value: str) -> str:
    return re.sub(r"[^0-9a-fA-F]", "", value).lower()


def _find_apksigner() -> str:
    executable = shutil.which("apksigner")
    if executable:
        return executable

    sdk_roots = [
        os.environ.get("ANDROID_SDK_ROOT", ""),
        os.environ.get("ANDROID_HOME", ""),
    ]
    candidates = []
    for raw_root in sdk_roots:
        if not raw_root:
            continue
        candidates.extend(Path(raw_root).glob("build-tools/*/apksigner"))
    candidates = [path for path in candidates if path.is_file()]
    if not candidates:
        raise SystemExit("Android build-tools apksigner was not found.")
    return str(sorted(candidates, key=lambda path: path.parent.name)[-1])


def _certificate_fingerprint(path: Path) -> str:
    if path.suffix.lower() == ".apk":
        command = [_find_apksigner(), "verify", "--print-certs", str(path)]
        pattern = r"Signer #\d+ certificate SHA-256 digest:\s*([0-9a-fA-F:]+)"
    elif path.suffix.lower() == ".aab":
        keytool = shutil.which("keytool")
        if not keytool:
            raise SystemExit("Java keytool was not found; cannot verify the AAB certificate.")
        command = [keytool, "-printcert", "-jarfile", str(path)]
        pattern = r"SHA256:\s*([0-9a-fA-F:]+)"
    else:
        raise SystemExit(f"Unsupported Android release archive: {path}")

    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        details = (result.stderr or result.stdout).strip()
        raise SystemExit(
            f"Android signing verification failed for {path.name}: {details[-1200:]}"
        )
    match = re.search(pattern, result.stdout + "\n" + result.stderr, re.IGNORECASE)
    if match is None:
        raise SystemExit(
            f"Could not read the SHA-256 signing certificate from {path.name}."
        )
    fingerprint = _normalize_fingerprint(match.group(1))
    if len(fingerprint) != 64:
        raise SystemExit(f"Invalid SHA-256 signing certificate in {path.name}.")
    return fingerprint


def verify_signing(paths: list[Path], expected_fingerprint: str) -> None:
    expected = _normalize_fingerprint(expected_fingerprint)
    if len(expected) != 64:
        raise SystemExit("--expected-cert-sha256 must contain a 64-character SHA-256 fingerprint.")

    for path in paths:
        actual = _certificate_fingerprint(path)
        if actual != expected:
            raise SystemExit(
                f"Signing certificate mismatch for {path.name}; "
                "the artifact was not signed with the configured release key."
            )
        print(f"verified_signing_certificate={path.name} sha256={actual}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--aab", type=Path)
    parser.add_argument(
        "--expected-cert-sha256",
        help="Require APK and AAB to be signed by this SHA-256 certificate.",
    )
    args = parser.parse_args()
    archives = [path for path in (args.apk, args.aab) if path is not None]
    if not archives:
        parser.error("Provide --apk and/or --aab.")

    for archive in archives:
        for asset in verify(archive):
            print(f"verified={archive} asset={asset}")

    if args.expected_cert_sha256:
        if len(archives) != 2 or {path.suffix.lower() for path in archives} != {".apk", ".aab"}:
            parser.error("--expected-cert-sha256 requires both --apk and --aab.")
        verify_signing(archives, args.expected_cert_sha256)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
