#!/usr/bin/env python3
"""Builds a one-page PDF whose image is JPEG 2000 (/JPXDecode).

Usage: make_jpx_pdf.py out.pdf
A test PNG is generated here and converted to JPEG 2000 with macOS `sips`
(CoreGraphics cannot write JPX into a PDF), so no binary asset needs to live
in the repository."""
import os
import struct
import subprocess
import sys
import tempfile
import zlib


def test_png(width=320, height=200):
    """A deterministic RGB gradient/XOR pattern as PNG bytes."""
    raw = b"".join(
        b"\x00" + b"".join(bytes(((x * 255) // width, (y * 255) // height, (x ^ y) & 255)) for x in range(width))
        for y in range(height)
    )
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")


with tempfile.TemporaryDirectory() as tmp:
    png, jp2_path = os.path.join(tmp, "img.png"), os.path.join(tmp, "img.jp2")
    with open(png, "wb") as f:
        f.write(test_png())
    subprocess.run(["sips", "-s", "format", "jp2", png, "--out", jp2_path], check=True, capture_output=True)
    jp2 = open(jp2_path, "rb").read()

# Image size from the JP2 'ihdr' box: height, width as big-endian u32.
i = jp2.index(b"ihdr")
height, width = struct.unpack(">II", jp2[i + 4:i + 12])

content = b"q 400 0 0 %d 106 300 cm /Im1 Do Q BT /F1 18 Tf 72 720 Td (JPEG 2000) Tj ET" % (400 * height // width)
objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
    b"/Resources << /Font << /F1 6 0 R >> /XObject << /Im1 5 0 R >> >> >>",
    b"<< /Length %d >>\nstream\n%s\nendstream" % (len(content), content),
    b"<< /Type /XObject /Subtype /Image /Width %d /Height %d /Filter /JPXDecode "
    b"/Length %d >>\nstream\n%s\nendstream" % (width, height, len(jp2), jp2),
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
]

out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
offsets = [0]
for n, body in enumerate(objects, start=1):
    offsets.append(len(out))
    out += b"%d 0 obj\n%s\nendobj\n" % (n, body)
xref = len(out)
out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
out += b"".join(b"%010d 00000 n \n" % o for o in offsets[1:])
out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref)
open(sys.argv[1], "wb").write(out)
print(f"wrote {sys.argv[1]} ({width}x{height} JPX)")
