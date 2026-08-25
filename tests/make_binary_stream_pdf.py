#!/usr/bin/env python3
"""Builds a benign PDF whose image stream deliberately contains the byte
sequences "/JS" and "/JavaScript" inside binary stream data. Regression test
for the raw-scan false positive: marker bytes inside stream contents (e.g.
JPEG data) must NOT be reported."""
import sys

content = b"BT /F1 24 Tf 72 700 Td (Harmlose Seite) Tj ET"
# Binary garbage that happens to contain marker byte sequences.
garbage = b"\x00\x11\x22/JS\x99\xfe binary /JavaScript\xba\xad more bytes \xde\xad\xbe\xef" * 3

objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
    b"/Resources << /Font << /F1 6 0 R >> >> /Contents 4 0 R >>",
    b"<< /Length %d >>\nstream\n%s\nendstream" % (len(content), content),
    b"<< /Length %d >>\nstream\n%s\nendstream" % (len(garbage), garbage),
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
]

out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
offsets = [0]
for i, body in enumerate(objects, start=1):
    offsets.append(len(out))
    out += b"%d 0 obj\n%s\nendobj\n" % (i, body)

xref_pos = len(out)
out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
for off in offsets[1:]:
    out += b"%010d 00000 n \n" % off
out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref_pos)

with open(sys.argv[1], "wb") as f:
    f.write(out)
print(f"wrote {sys.argv[1]} ({len(out)} bytes)")
