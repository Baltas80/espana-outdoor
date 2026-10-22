#!/usr/bin/env python3
"""Generate a tiny valid PMTiles v3 vector archive for Android offline smoke tests."""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path


def varint(value: int) -> bytes:
    if value < 0:
        raise ValueError("varint requires a non-negative integer")
    out = bytearray()
    while value >= 0x80:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)


def build_fixture() -> bytes:
    # Include an actual, visible polygon so the Android smoke can distinguish
    # successful local PMTiles reads from an empty beige background.
    geometry = bytes(
        (
            9, 128, 8, 128, 8,  # MoveTo (512, 512)
            26, 128, 48, 0, 0, 128, 48, 255, 47, 0,  # 3 LineTo points
            15,  # ClosePath
        )
    )
    feature = (
        b"\x08\x01"  # id = 1
        b"\x12\x02\x00\x00"  # class = wood (key 0, value 0)
        b"\x18\x03"  # polygon geometry type
        + b"\x22"
        + varint(len(geometry))
        + geometry
    )
    value = b"\x0a\x04wood"
    layer = (
        b"\x0a\x09landcover"
        + b"\x12"
        + varint(len(feature))
        + feature
        + b"\x1a\x05class"
        + b"\x22"
        + varint(len(value))
        + value
        + b"\x28\x80\x20"  # extent = 4096
        + b"\x78\x02"  # MVT layer version = 2
    )
    tile = b"\x1a" + varint(len(layer)) + layer

    # PMTiles v3 directory entries are delta-encoded tile IDs followed by
    # run-length, length and offset. Keep two real entries and one deduplicated
    # tile blob. The previous fixture put the tile count into a run-length
    # field, producing a structurally invalid directory that could build but
    # could not be consumed reliably by the native PMTiles provider.
    tile_length = len(tile)
    root = b"".join(
        (
            varint(2),  # number of directory entries
            varint(0),  # first tile-id delta
            varint(1),  # first run length
            varint(tile_length),
            varint(0),  # first tile-data offset
            varint(1),  # second tile-id delta
            varint(1),  # second run length
            varint(tile_length),
            varint(0),  # second offset follows the first tile immediately
        )
    )

    metadata = json.dumps(
        {
            "tilejson": "3.0.0",
            "name": "España Outdoor offline smoke",
            "format": "pbf",
            "version": "1",
            "type": "overlay",
            "minzoom": 0,
            "maxzoom": 6,
            "bounds": [-18, 35, 5, 44],
            "center": [-3.7038, 40.4168, 6],
            "vector_layers": [{"id": "landcover", "fields": {"class": "String"}}],
        },
        separators=(",", ":"),
    ).encode("utf-8")

    header = bytearray(127)
    header[0:7] = b"PMTiles"
    header[7] = 3

    root_offset = 127
    root_length = len(root)
    metadata_offset = root_offset + root_length
    metadata_length = len(metadata)
    tile_data_offset = metadata_offset + metadata_length
    tile_data_length = tile_length * 2

    values = (
        root_offset,
        root_length,
        metadata_offset,
        metadata_length,
        0,
        0,
        tile_data_offset,
        tile_data_length,
        2,
        2,
        1,
    )
    offset = 8
    for value in values:
        struct.pack_into("<Q", header, offset, value)
        offset += 8

    header[96] = 1
    header[97] = 1
    header[98] = 1
    header[99] = 1  # PMTiles TileType.Mvt
    header[100] = 0
    header[101] = 6
    struct.pack_into("<i", header, 102, -180000000)
    struct.pack_into("<i", header, 106, 350000000)
    struct.pack_into("<i", header, 110, 50000000)
    struct.pack_into("<i", header, 114, 440000000)
    header[118] = 6
    struct.pack_into("<i", header, 119, -37038000)
    struct.pack_into("<i", header, 123, 404168000)

    return bytes(header) + root + metadata + tile + tile


def main() -> int:
    output = Path(sys.argv[1] if len(sys.argv) > 1 else "assets/testing/offline_smoke.pmtiles")
    output.parent.mkdir(parents=True, exist_ok=True)
    data = build_fixture()
    output.write_bytes(data)

    if len(data) < 127:
        raise SystemExit("Generated PMTiles fixture is too small.")
    if data[:7] != b"PMTiles" or data[7] != 3:
        raise SystemExit("Generated fixture has an invalid PMTiles header.")
    if data[97] != 1 or data[98] != 1 or data[99] != 1:
        raise SystemExit("Fixture must use uncompressed MVT tile payloads.")
    if int.from_bytes(data[8:16], "little") + int.from_bytes(data[16:24], "little") > 16384:
        raise SystemExit("Generated root directory is outside the 16 KiB PMTiles bootstrap window.")

    metadata_offset = int.from_bytes(data[24:32], "little")
    metadata_length = int.from_bytes(data[32:40], "little")
    json.loads(data[metadata_offset : metadata_offset + metadata_length].decode("utf-8"))

    root_offset = int.from_bytes(data[8:16], "little")
    root_length = int.from_bytes(data[16:24], "little")
    root_bytes = data[root_offset : root_offset + root_length]
    if root_bytes[:1] != b"\x02":
        raise SystemExit("Generated PMTiles root directory does not contain two entries.")

    print(f"Generated {output} ({len(data)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
