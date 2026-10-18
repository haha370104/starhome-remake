#!/usr/bin/env python3
"""Decode FancyBoxII PKH navigation payloads using the client's LZW variant."""

from __future__ import annotations

import argparse
from pathlib import Path


CLEAR = 0x100
END = 0x101
FIRST_DYNAMIC = 0x102
MAX_CODE_BITS = 12


def read_code(payload: bytes, bit_position: int, width: int) -> tuple[int, int]:
    """Read one least-significant-bit-first code from the packed stream."""
    byte_position = bit_position >> 3
    if bit_position + width > len(payload) * 8:
        raise ValueError("truncated PKH code stream")
    word = int.from_bytes(payload[byte_position : byte_position + 4].ljust(4, b"\0"), "little")
    return (word >> (bit_position & 7)) & ((1 << width) - 1), bit_position + width


def decode(payload: bytes, max_output_size: int = 64 * 1024 * 1024) -> bytes:
    """Decode a PKH payload with its four-byte uncompressed-size prefix."""
    if len(payload) < 4:
        raise ValueError("PKH payload is missing its size prefix")
    expected_size = int.from_bytes(payload[:4], "little")
    if expected_size > max_output_size:
        raise ValueError("PKH output exceeds configured size limit")
    payload = payload[4:]
    output = bytearray()
    bit_position = 0
    width = 9
    next_code = FIRST_DYNAMIC
    dictionary = [bytes((index,)) for index in range(256)] + [b"", b""]
    previous: bytes | None = None

    while True:
        code, bit_position = read_code(payload, bit_position, width)
        if code == END:
            if len(output) != expected_size:
                raise ValueError(
                    f"PKH size prefix is {expected_size}, decoded {len(output)} bytes"
                )
            return bytes(output)
        if code == CLEAR:
            width = 9
            next_code = FIRST_DYNAMIC
            dictionary = [bytes((index,)) for index in range(256)] + [b"", b""]
            previous = None
            continue
        if code >= (1 << width) or code >= len(dictionary) and code != next_code:
            raise ValueError(f"invalid PKH code: 0x{code:x}")

        if previous is None:
            if code >= 256:
                raise ValueError(f"first PKH code is not a literal: 0x{code:x}")
            current = bytes((code,))
        elif code < next_code:
            current = dictionary[code]
        elif code == next_code:
            current = previous + previous[:1]
        else:
            raise ValueError(f"invalid PKH forward reference: 0x{code:x}")

        if len(output) + len(current) > expected_size:
            raise ValueError("PKH output exceeds declared size")
        output.extend(current)
        if previous is not None:
            if next_code >= (1 << MAX_CODE_BITS):
                raise ValueError("PKH dictionary exceeded 12-bit limit without clear")
            dictionary.append(previous + current[:1])
            next_code += 1
            if next_code >= (1 << width) and width < MAX_CODE_BITS:
                width += 1
        previous = current


def main() -> int:
    """Decode one packed PKH file to raw navigation bytes."""
    parser = argparse.ArgumentParser(
        description=(
            "Decode a PKH payload. Accepts the same three paths as the native "
            "wrapper (engine DLL, packed input, raw output); the engine path is "
            "ignored by this pure-Python fallback."
        )
    )
    parser.add_argument(
        "paths",
        nargs="+",
        type=Path,
        metavar="PATH",
        help="packed raw, or engine-dll packed raw",
    )
    args = parser.parse_args()
    if len(args.paths) == 2:
        packed_path, raw_path = args.paths
    elif len(args.paths) == 3:
        _engine_dll, packed_path, raw_path = args.paths
    else:
        parser.error("expected PACKED RAW or ENGINE_DLL PACKED RAW")
    raw_path.write_bytes(decode(packed_path.read_bytes()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
