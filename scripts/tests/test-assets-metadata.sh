#!/usr/bin/env bash
# The pictures published on GitHub (README cover and social preview) carry no metadata:
# their chunks are IHDR first, then sRGB and IDAT only, then IEND last.
set -euo pipefail
python3 - "$(dirname "$0")/../.." <<'PY'
from pathlib import Path
import struct, sys, zlib

root = Path(sys.argv[1])
SIGNATURE = b"\x89PNG\r\n\x1a\n"
ALLOWED = {"IHDR", "sRGB", "IDAT", "IEND"}


def chunk(kind, data):
    body = kind.encode() + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))


def split(raw):
    """Returns the (type, bytes) chunks, or raises ValueError on a malformed file."""
    if raw[:8] != SIGNATURE:
        raise ValueError("signature")
    out, offset = [], 8
    while offset < len(raw):
        if offset + 12 > len(raw):
            raise ValueError("truncated header")
        length, = struct.unpack(">I", raw[offset:offset + 4])
        end = offset + 12 + length
        if end > len(raw):
            raise ValueError("truncated data")
        kind = raw[offset + 4:offset + 8]
        crc, = struct.unpack(">I", raw[end - 4:end])
        if zlib.crc32(raw[offset + 4:end - 4]) != crc:
            raise ValueError("crc")
        out.append((kind.decode("latin-1"), raw[offset:end]))
        offset = end
    return out


def problem(raw):
    """Returns None for a bare PNG, or the reason it is not one."""
    try:
        chunks = split(raw)
    except ValueError as error:
        return str(error)
    kinds = [kind for kind, _ in chunks]
    if not kinds or kinds[0] != "IHDR" or kinds.count("IHDR") != 1:
        return "IHDR"
    if kinds[-1] != "IEND" or kinds.count("IEND") != 1:
        return "IEND"
    if "IDAT" not in kinds:
        return "IDAT"
    extra = sorted(set(kinds) - ALLOWED)
    if extra:
        return "extra " + ",".join(extra)
    return None


for name in ["Assets/cover.png", "Assets/social-preview.png"]:
    raw = (root / name).read_bytes()
    assert problem(raw) is None, (name, problem(raw))

# Every malformed or metadata-carrying variant of a real file must be rejected.
raw = (root / "Assets/social-preview.png").read_bytes()
chunks = split(raw)
ancillary = [
    chunk("eXIf", b"MM\x00*\x00\x00\x00\x08\x00\x00"),
    chunk("pHYs", struct.pack(">IIB", 5669, 5669, 1)),
    chunk("tEXt", b"Author\x00someone"),
    chunk("iTXt", b"XML:com.adobe.xmp\x00\x00\x00\x00\x00<x/>"),
    chunk("zTXt", b"Comment\x00\x00" + zlib.compress(b"x")),
    chunk("tIME", struct.pack(">HBBBBB", 2026, 1, 1, 0, 0, 0)),
    chunk("iCCP", b"P3\x00\x00" + zlib.compress(b"profile")),
    chunk("gAMA", struct.pack(">I", 45455)),
    chunk("prVt", b"private"),
]
cases = 0
for extra in ancillary:
    # Before IDAT, between the IDATs, and right before IEND.
    for position in (1, len(chunks) // 2, len(chunks) - 1):
        mutated = [c for _, c in chunks]
        mutated.insert(position, extra)
        assert problem(SIGNATURE + b"".join(mutated)) is not None, (extra[4:8], position)
        cases += 1
body = [c for _, c in chunks]
malformed = {
    "data after IEND": raw + chunk("tEXt", b"k\x00v"),
    "second IEND": raw + chunk("IEND", b""),
    "missing IEND": SIGNATURE + b"".join(body[:-1]),
    "IHDR not first": SIGNATURE + b"".join([body[1], body[0]] + body[2:]),
    "second IHDR": SIGNATURE + b"".join(body[:1] + body),
    "no IDAT": SIGNATURE + b"".join(c for k, c in chunks if k != "IDAT"),
    "truncated": raw[:-3],
    "truncated header": raw + b"\x00\x00",
    "bad signature": b"\x88" + raw[1:],
    "bad crc": raw[:-1] + bytes([raw[-1] ^ 1]),
    "empty": b"",
}
for label, data in malformed.items():
    assert problem(data) is not None, label
    cases += 1
print(f"PASS published PNGs carry no metadata; {cases} rejected variants")
PY
