#!/usr/bin/env python3
"""Parse a decoded FTC1 files_dir.dz index into an auditable resource CSV."""

import argparse
import csv
import hashlib
import re
from pathlib import Path

ALPHABET = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_`abcdefghijklmnopqrstuvwxyz"
VALUE = {c: i for i, c in enumerate(ALPHABET)}
MD5_RE = re.compile(br"^[0-9A-Fa-f]{32}$")

def decode64_be(raw: bytes) -> int:
    n = 0
    for c in raw:
        if c not in VALUE:
            raise ValueError(f"invalid custom-base64 byte 0x{c:02x} in {raw!r}")
        n = n * 64 + VALUE[c]
    return n

def restore_path(encoded: bytes, previous_valid: bytes) -> bytes:
    if encoded[:1] in (b"+", b"*"):
        if len(encoded) < 2:
            raise ValueError("compressed path marker without prefix-length byte")
        prefix_len = decode64_be(encoded[1:2])
        if prefix_len > len(previous_valid):
            raise ValueError(
                f"prefix length {prefix_len} exceeds previous valid path length "
                f"{len(previous_valid)}"
            )
        return previous_valid[:prefix_len] + encoded[2:]
    return encoded

def decode_path(raw: bytes) -> str:
    return raw.decode("gbk", errors="strict")

def main():
    ap = argparse.ArgumentParser(
        description="Parse decoded FancyBoxII files_dir.dz resource index."
    )
    ap.add_argument("input", type=Path)
    ap.add_argument(
        "--csv", type=Path, default=Path("resource_index.csv"),
        help="output audit CSV (default: resource_index.csv)"
    )
    args = ap.parse_args()

    data = args.input.read_bytes()
    lines = data.splitlines()

    previous_valid = b""
    valid = []
    tombstones = []
    errors = []

    for lineno, line in enumerate(lines, 1):
        line = line.rstrip(b"\r")
        if not line:
            continue

        # Valid records: path,version,size,md5
        # Tombstones:    path,version,size   (no MD5)
        parts = line.rsplit(b",", 3)

        try:
            if len(parts) == 4 and MD5_RE.match(parts[3]):
                encoded_path, version_code, size_code, md5_raw = parts
                path_bytes = restore_path(encoded_path, previous_valid)
                logical_path = decode_path(path_bytes)
                size = decode64_be(size_code)

                valid.append({
                    "line": lineno,
                    "logical_path": logical_path,
                    "path_bytes_hex": path_bytes.hex(),
                    "encoded_path_hex": encoded_path.hex(),
                    "version_code": version_code.decode("ascii", "replace"),
                    "size_code": size_code.decode("ascii", "replace"),
                    "size": size,
                    "md5": md5_raw.decode("ascii").lower(),
                    "kind": "valid",
                })
                previous_valid = path_bytes
            else:
                # For tombstones, split into exactly 3 fields from the right.
                tparts = line.rsplit(b",", 2)
                if len(tparts) != 3:
                    raise ValueError(f"unexpected field count: {len(parts)}")
                encoded_path, version_code, size_code = tparts
                path_bytes = restore_path(encoded_path, previous_valid)
                logical_path = decode_path(path_bytes)

                tombstones.append({
                    "line": lineno,
                    "logical_path": logical_path,
                    "path_bytes_hex": path_bytes.hex(),
                    "encoded_path_hex": encoded_path.hex(),
                    "version_code": version_code.decode("ascii", "replace"),
                    "size_code": size_code.decode("ascii", "replace"),
                    "size": "",
                    "md5": "",
                    "kind": "tombstone",
                })
                # IMPORTANT: tombstones do NOT update previous_valid.
        except Exception as e:
            errors.append((lineno, line[:160], str(e)))

    rows = valid + tombstones
    rows.sort(key=lambda r: r["line"])
    args.csv.parent.mkdir(parents=True, exist_ok=True)
    with args.csv.open("w", encoding="utf-8-sig", newline="") as f:
        fields = [
            "line", "kind", "logical_path", "path_bytes_hex",
            "encoded_path_hex", "version_code", "size_code", "size", "md5"
        ]
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

    paths = [r["logical_path"] for r in valid]
    duplicate_paths = len(paths) - len(set(paths))
    total_size = sum(r["size"] for r in valid)

    print(f"input bytes:       {len(data):,}")
    print(f"non-empty lines:   {sum(bool(x.rstrip(b'\\r')) for x in lines):,}")
    print(f"valid records:     {len(valid):,}")
    print(f"tombstones:        {len(tombstones):,}")
    print(f"errors:            {len(errors):,}")
    print(f"duplicate paths:   {duplicate_paths:,}")
    print(f"decoded total size:{total_size:,} bytes")
    print(f"csv:               {args.csv}")

    print("\nfirst 10 valid records:")
    for r in valid[:10]:
        print(f"  {r['size']:>10,}  {r['md5']}  {r['logical_path']}")

    if errors:
        print("\nfirst errors:")
        for lineno, raw, err in errors[:20]:
            print(f"  line {lineno}: {err}; raw={raw!r}")

    # Known historical values from the project's recovery notes.
    expected_valid = 18975
    expected_tomb = 638
    expected_bytes = 2032740770
    print("\nknown-history cross-check:")
    print(f"  valid:      {'MATCH' if len(valid)==expected_valid else 'DIFF'} "
          f"({len(valid):,} vs {expected_valid:,})")
    print(f"  tombstones: {'MATCH' if len(tombstones)==expected_tomb else 'DIFF'} "
          f"({len(tombstones):,} vs {expected_tomb:,})")
    print(f"  bytes:      {'MATCH' if total_size==expected_bytes else 'DIFF'} "
          f"({total_size:,} vs {expected_bytes:,})")

if __name__ == "__main__":
    main()
