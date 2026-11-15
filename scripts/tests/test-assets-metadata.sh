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
    """Validates the two published RGBA8 PNGs, including their compressed data."""
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
    # The two published images use the renderer's non-interlaced RGBA8 profile.
    if (kinds.count("sRGB") != 1 or kinds[1] != "sRGB"
            or any(kind != "IDAT" for kind in kinds[2:-1])):
        return "chunk order"
    header = chunks[0][1][8:-4]
    if len(header) != 13:
        return "IHDR length"
    width, height, depth, color, compression, filtering, interlace = struct.unpack(
        ">IIBBBBB", header)
    if (width, height) not in {(2560, 1280), (1280, 640)}:
        return "dimensions"
    if (depth, color, compression, filtering, interlace) != (8, 6, 0, 0, 0):
        return "RGBA8 profile"
    if chunks[1][1][8:-4] not in (b"\x00", b"\x01", b"\x02", b"\x03"):
        return "sRGB intent"
    if chunks[-1][1][8:-4]:
        return "IEND length"
    packed = b"".join(c[8:-4] for kind, c in chunks if kind == "IDAT")
    stride = width * 4 + 1
    expected = stride * height
    decoder = zlib.decompressobj()
    try:
        pixels = decoder.decompress(packed, expected + 1)
    except zlib.error:
        return "IDAT zlib"
    if (len(pixels) != expected or not decoder.eof
            or decoder.unused_data or decoder.unconsumed_tail):
        return "IDAT length"
    if any(pixels[offset] > 4 for offset in range(0, expected, stride)):
        return "scanline filter"
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

# Negative properties for allowed chunk types: cardinality, order, payload and range.
def image(parts):
    return SIGNATURE + b"".join(parts)


header = body[0][8:-4]
srgb = next(c for kind, c in chunks if kind == "sRGB")
idats = [c for kind, c in chunks if kind == "IDAT"]
compressed = b"".join(c[8:-4] for c in idats)
pixels = zlib.decompress(compressed)


def replace(kind, payload):
    return image([chunk(kind, payload) if k == kind else c for k, c in chunks])


properties = {
    "duplicate sRGB": image(body[:2] + [srgb] + body[2:]),
    "missing sRGB": image([c for k, c in chunks if k != "sRGB"]),
    "sRGB after IDAT": image([body[0]] + idats + [srgb, body[-1]]),
    "sRGB interrupts IDAT": image(
        [body[0], idats[0], srgb] + idats[1:] + [body[-1]]),
    "short IHDR": replace("IHDR", header[:-1]),
    "extra IHDR byte": replace("IHDR", header + b"\x00"),
    "empty sRGB": replace("sRGB", b""),
    "extra sRGB byte": replace("sRGB", b"\x00\x00"),
    "IEND with payload": replace("IEND", b"x"),
}
for field, values in enumerate([
    (0, 0x80000000), (0, 0x80000000), (0, 7, 16),
    (1, 3, 5), (1, 255), (1, 255), (1, 255),
]):
    for value in values:
        fields = list(struct.unpack(">IIBBBBB", header))
        fields[field] = value
        properties[f"IHDR field {field} value {value}"] = replace(
            "IHDR", struct.pack(">IIBBBBB", *fields))
for intent in (4, 255):
    properties[f"sRGB intent {intent}"] = replace("sRGB", bytes([intent]))
for label, data in {
    "empty": b"", "truncated": compressed[:-1],
    "garbage": b"garbage", "trailing": compressed + b"x",
    "short rows": zlib.compress(pixels[:-1]),
    "extra row byte": zlib.compress(pixels + b"x"),
    "bad filter": zlib.compress(b"\x05" + pixels[1:]),
}.items():
    properties[f"IDAT {label}"] = image(
        [body[0], srgb, chunk("IDAT", data), body[-1]])
for label, data in properties.items():
    assert problem(data) is not None, label
    cases += 1

# Chunk boundaries may move; an empty individual IDAT remains legal.
for parts in (
    [body[0], srgb, chunk("IDAT", compressed), body[-1]],
    [body[0], srgb, chunk("IDAT", b"")] + idats + [body[-1]],
):
    assert problem(image(parts)) is None

print(f"PASS published PNGs carry no metadata; {cases} rejected variants")
PY
