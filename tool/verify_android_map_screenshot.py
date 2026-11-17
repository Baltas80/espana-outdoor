#!/usr/bin/env python3
"""Validate a host-captured Android PNG of the Mapbox viewport without third-party packages."""
from __future__ import annotations

import argparse
import math
import struct
import sys
import zlib
from collections import Counter
from pathlib import Path

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MAX_DIMENSION = 10000
MAX_PIXELS = 40_000_000


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def decode_png(payload: bytes) -> tuple[int, int, int, bytes]:
    if not payload.startswith(PNG_SIGNATURE):
        raise ValueError("screenshot is not a PNG")
    offset = len(PNG_SIGNATURE)
    width = height = bit_depth = color_type = interlace = None
    compressed = bytearray()
    saw_end = False
    while offset + 12 <= len(payload):
        length = struct.unpack_from(">I", payload, offset)[0]
        offset += 4
        kind = payload[offset : offset + 4]
        offset += 4
        if length > len(payload) - offset - 4:
            raise ValueError("truncated PNG chunk")
        data = payload[offset : offset + length]
        offset += length
        crc = struct.unpack_from(">I", payload, offset)[0]
        offset += 4
        if zlib.crc32(kind + data) & 0xFFFFFFFF != crc:
            raise ValueError("PNG chunk checksum mismatch")
        if kind == b"IHDR":
            if length != 13:
                raise ValueError("invalid PNG header")
            width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(
                ">IIBBBBB", data
            )
            if compression != 0 or filtering != 0 or interlace != 0:
                raise ValueError("unsupported PNG compression, filter, or interlace mode")
            if bit_depth != 8 or color_type not in (2, 6):
                raise ValueError("only 8-bit RGB/RGBA Android screenshots are supported")
            if not (1 <= width <= MAX_DIMENSION and 1 <= height <= MAX_DIMENSION):
                raise ValueError("PNG dimensions are outside the accepted range")
            if width * height > MAX_PIXELS:
                raise ValueError("PNG pixel count is outside the accepted range")
        elif kind == b"IDAT":
            compressed.extend(data)
        elif kind == b"IEND":
            saw_end = True
            break
    if width is None or height is None or not saw_end or not compressed:
        raise ValueError("PNG is missing required chunks")

    channels = 4 if color_type == 6 else 3
    stride = width * channels
    raw = zlib.decompress(bytes(compressed))
    if len(raw) != height * (stride + 1):
        raise ValueError("PNG decompressed size does not match its dimensions")

    pixels = bytearray(height * stride)
    src = 0
    previous = bytearray(stride)
    for y in range(height):
        filter_type = raw[src]
        src += 1
        scanline = bytearray(raw[src : src + stride])
        src += stride
        if filter_type == 1:
            for i in range(stride):
                left = scanline[i - channels] if i >= channels else 0
                scanline[i] = (scanline[i] + left) & 0xFF
        elif filter_type == 2:
            for i in range(stride):
                scanline[i] = (scanline[i] + previous[i]) & 0xFF
        elif filter_type == 3:
            for i in range(stride):
                left = scanline[i - channels] if i >= channels else 0
                scanline[i] = (scanline[i] + ((left + previous[i]) // 2)) & 0xFF
        elif filter_type == 4:
            for i in range(stride):
                left = scanline[i - channels] if i >= channels else 0
                up = previous[i]
                upper_left = previous[i - channels] if i >= channels else 0
                scanline[i] = (scanline[i] + _paeth(left, up, upper_left)) & 0xFF
        elif filter_type != 0:
            raise ValueError(f"unsupported PNG row filter {filter_type}")
        start = y * stride
        pixels[start : start + stride] = scanline
        previous = scanline
    return width, height, channels, bytes(pixels)


def analyze_png(payload: bytes) -> dict[str, float | int]:
    width, height, channels, pixels = decode_png(payload)
    if width < 300 or height < 300:
        raise ValueError("screenshot viewport is too small")
    min_x, max_x = round(width * 0.08), round(width * 0.92)
    min_y, max_y = round(height * 0.12), round(height * 0.88)
    counts: Counter[int] = Counter()
    sampled = opaque = 0
    for y in range(min_y, max_y, 16):
        row = y * width * channels
        for x in range(min_x, max_x, 16):
            offset = row + x * channels
            red, green, blue = pixels[offset : offset + 3]
            alpha = pixels[offset + 3] if channels == 4 else 255
            sampled += 1
            if alpha >= 240:
                opaque += 1
            key = ((red >> 4) << 12) | ((green >> 4) << 8) | ((blue >> 4) << 4) | (alpha >> 4)
            counts[key] += 1
    if not sampled:
        raise ValueError("screenshot contains no sampled viewport pixels")
    entropy = -sum((n / sampled) * math.log2(n / sampled) for n in counts.values())
    return {
        "width": width,
        "height": height,
        "unique_colors": len(counts),
        "opaque_ratio": opaque / sampled,
        "entropy_bits": entropy,
        "dominant_ratio": max(counts.values()) / sampled,
        "dominant_color_key": max(counts, key=counts.get),
    }


def _expected_color_key(value: str) -> int:
    if len(value) != 7 or value[0] != "#":
        raise ValueError("expected solid color must use #RRGGBB")
    try:
        red, green, blue = (int(value[index : index + 2], 16) for index in (1, 3, 5))
    except ValueError as error:
        raise ValueError("expected solid color must use #RRGGBB") from error
    return ((red >> 4) << 12) | ((green >> 4) << 8) | ((blue >> 4) << 4) | 0xF


def verify_expected_solid_color(
    metrics: dict[str, float | int], expected_color: str
) -> list[str]:
    failures: list[str] = []
    if metrics["dominant_color_key"] != _expected_color_key(expected_color):
        failures.append("expected_background_color")
    if metrics["unique_colors"] > 128:
        failures.append("solid_style_unique_colors")
    if metrics["opaque_ratio"] <= 0.95:
        failures.append("opaque_ratio")
    if metrics["entropy_bits"] > 1.2:
        failures.append("solid_style_entropy")
    if metrics["dominant_ratio"] < 0.85:
        failures.append("solid_style_dominant_ratio")
    return failures


def _self_test() -> None:
    width = height = 400
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            rows.extend(((x * 17 + y * 3) & 255, (x * 5 + y * 19) & 255, (x * 11 + y * 7) & 255, 255))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = PNG_SIGNATURE + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(rows))) + chunk(b"IEND", b"")
    metrics = analyze_png(png)
    assert metrics["unique_colors"] > 24
    assert metrics["entropy_bits"] > 1.2

    solid_rows = bytearray()
    for _ in range(height):
        solid_rows.append(0)
        for _ in range(width):
            solid_rows.extend((217, 230, 199, 255))
    solid_png = PNG_SIGNATURE + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(solid_rows))) + chunk(b"IEND", b"")
    solid_metrics = analyze_png(solid_png)
    assert verify_expected_solid_color(solid_metrics, "#d9e6c7") == []
    assert verify_expected_solid_color(solid_metrics, "#000000") == ["expected_background_color"]
    print("ANDROID_MAP_SCREENSHOT_SELF_TEST passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("png", nargs="?", type=Path)
    parser.add_argument("--foreground-package")
    parser.add_argument("--expected-solid-color")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            _self_test()
            return 0
        if args.png is None:
            parser.error("provide a PNG path or --self-test")
        foreground_package = (args.foreground_package or "").strip()
        if not foreground_package or not all(ch.isalnum() or ch in "._" for ch in foreground_package):
            parser.error("real screenshot validation requires a verified --foreground-package")
        print(f"MAPBOX_OFFLINE_SCREENSHOT_FOREGROUND package={foreground_package} verified=true")
        metrics = analyze_png(args.png.read_bytes())
        print(
            "MAPBOX_OFFLINE_SCREENSHOT_METRICS "
            f"width={metrics['width']} height={metrics['height']} "
            f"unique_colors={metrics['unique_colors']} "
            f"opaque_ratio={metrics['opaque_ratio']:.3f} "
            f"entropy_bits={metrics['entropy_bits']:.3f} "
            f"dominant_ratio={metrics['dominant_ratio']:.3f} "
            f"dominant_color_key={metrics['dominant_color_key']:04x}"
        )
        if args.expected_solid_color:
            print(
                "MAPBOX_OFFLINE_RENDER_GATE mode=solid "
                f"expected_color={args.expected_solid_color} dominant_min=0.90"
            )
            failures = verify_expected_solid_color(metrics, args.expected_solid_color)
        else:
            print("MAPBOX_OFFLINE_RENDER_GATE version=3 entropy_min=1.2 dominant_max=0.85")
            failures = []
            if metrics["unique_colors"] <= 24:
                failures.append("unique_colors")
            if metrics["opaque_ratio"] <= 0.95:
                failures.append("opaque_ratio")
            if metrics["entropy_bits"] <= 1.2:
                failures.append("entropy_bits")
            if metrics["dominant_ratio"] >= 0.85:
                failures.append("dominant_ratio")
        if failures:
            print("MAPBOX_OFFLINE_SCREENSHOT_REJECTED checks=" + ",".join(failures), file=sys.stderr)
            return 1
        print("MAPBOX_OFFLINE_MAP_RENDERED screenshot_source=adb")
        return 0
    except (OSError, ValueError, zlib.error, struct.error) as error:
        print(f"MAPBOX_OFFLINE_SCREENSHOT_ERROR type={type(error).__name__}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
