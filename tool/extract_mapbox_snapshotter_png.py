#!/usr/bin/env python3
"""Reassemble the staging-only Mapbox Snapshotter PNG emitted in Android logcat."""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import re
import struct
import sys
import zlib
from pathlib import Path

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
def capture_prefix(kind: str) -> str:
    if kind == "baseline":
        return "MAPBOX_SNAPSHOTTER_PNG"
    if kind == "vector":
        return "MAPBOX_SNAPSHOTTER_VECTOR_PNG"
    raise ValueError(f"unsupported Snapshotter capture kind: {kind}")


def decode_log_lines(lines: list[str], kind: str = "baseline") -> tuple[bytes, int, int]:
    prefix = capture_prefix(kind)
    chunk_re = re.compile(
        rf"{re.escape(prefix)}_CHUNK index=(\d+) total=(\d+) data=([A-Za-z0-9+/=]+)"
    )
    begin_re = re.compile(
        rf"{re.escape(prefix)}_BEGIN bytes=(\d+) chunks=(\d+) sha256=([0-9a-f]{{64}})"
    )
    end_re = re.compile(rf"{re.escape(prefix)}_END sha256=([0-9a-f]{{64}})")
    chunks: dict[int, str] = {}
    expected_total: int | None = None
    expected_bytes: int | None = None
    expected_digest: str | None = None
    end_digest: str | None = None

    for line in lines:
        begin = begin_re.search(line)
        if begin:
            expected_bytes = int(begin.group(1))
            expected_total = int(begin.group(2))
            expected_digest = begin.group(3)
        match = chunk_re.search(line)
        if match:
            index, total = int(match.group(1)), int(match.group(2))
            if total < 1 or index < 0 or index >= total:
                raise ValueError("snapshotter chunk index/total is invalid")
            if expected_total is not None and total != expected_total:
                raise ValueError("snapshotter chunk total changed within one capture")
            expected_total = total
            if index in chunks and chunks[index] != match.group(3):
                raise ValueError(f"snapshotter chunk {index} was duplicated with different data")
            chunks[index] = match.group(3)
        end = end_re.search(line)
        if end:
            end_digest = end.group(1)

    if expected_total is None or expected_bytes is None or expected_digest is None:
        raise ValueError("snapshotter capture header is missing")
    if len(chunks) != expected_total:
        missing = sorted(set(range(expected_total)) - set(chunks))
        raise ValueError(f"snapshotter capture is incomplete; missing chunks: {missing[:12]}")
    encoded = "".join(chunks[index] for index in range(expected_total))
    try:
        payload = base64.b64decode(encoded, validate=True)
    except (binascii.Error, ValueError) as error:
        raise ValueError(f"snapshotter base64 is invalid: {error}") from error

    if len(payload) != expected_bytes:
        raise ValueError(
            f"snapshotter byte count mismatch: expected {expected_bytes}, got {len(payload)}"
        )
    digest = hashlib.sha256(payload).hexdigest()
    if digest != expected_digest or (end_digest is not None and digest != end_digest):
        raise ValueError("snapshotter SHA-256 does not match its logcat manifest")
    if not payload.startswith(PNG_SIGNATURE):
        raise ValueError("snapshotter payload is not a PNG")
    if len(payload) < 24 or payload[12:16] != b"IHDR":
        raise ValueError("snapshotter PNG has no valid IHDR chunk")
    width, height = struct.unpack(">II", payload[16:24])
    if width < 1 or height < 1 or width > 10000 or height > 10000:
        raise ValueError("snapshotter PNG dimensions are outside accepted bounds")
    return payload, width, height


def _png_chunk(kind: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", binascii.crc32(kind + data) & 0xFFFFFFFF)
    )


def _self_test() -> None:
    raw = b"\x00\xff\x00\x00"
    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    png = (
        PNG_SIGNATURE
        + _png_chunk(b"IHDR", ihdr)
        + _png_chunk(b"IDAT", zlib.compress(raw))
        + _png_chunk(b"IEND", b"")
    )
    encoded = base64.b64encode(png).decode("ascii")
    chunk_size = 7
    parts = [encoded[i : i + chunk_size] for i in range(0, len(encoded), chunk_size)]
    digest = hashlib.sha256(png).hexdigest()

    for kind in ("baseline", "vector"):
        prefix = capture_prefix(kind)
        lines = [
            f"{prefix}_BEGIN bytes={len(png)} chunks={len(parts)} sha256={digest}",
            *[
                f"{prefix}_CHUNK index={index} total={len(parts)} data={part}"
                for index, part in enumerate(parts)
            ],
            f"{prefix}_END sha256={digest}",
        ]
        restored, width, height = decode_log_lines(lines, kind)
        assert restored == png and (width, height) == (1, 1)

        broken = lines[:-2] + lines[-1:]
        try:
            decode_log_lines(broken, kind)
        except ValueError:
            pass
        else:
            raise AssertionError(f"incomplete {kind} Snapshotter captures must be rejected")

    print("MAPBOX_SNAPSHOTTER_EXTRACTOR_SELF_TEST passed")

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--logcat", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--kind", choices=("baseline", "vector"), default="baseline")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        _self_test()
        return 0
    if args.logcat is None or args.output is None:
        parser.error("--logcat and --output are required unless --self-test is used")

    try:
        payload, width, height = decode_log_lines(
            args.logcat.read_text(encoding="utf-8", errors="replace").splitlines(),
            args.kind,
        )
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(payload)
    except (OSError, ValueError) as error:
        print(f"MAPBOX_SNAPSHOTTER_CAPTURE extracted=false reason={error}", file=sys.stderr)
        return 2

    digest = hashlib.sha256(payload).hexdigest()
    print(
        f"MAPBOX_SNAPSHOTTER_CAPTURE kind={args.kind} extracted=true "
        f"width={width} height={height} bytes={len(payload)} "
        f"sha256={digest} output={args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
