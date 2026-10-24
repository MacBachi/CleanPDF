#!/usr/bin/env python3
"""Builds a ~600-byte PDF with one page at the PDF maximum of 14400 x 14400 pt
(200 x 200 inches). Regression fixture for the render budget: without a cap,
rendering this at 200 dpi needs a 1.6-gigapixel bitmap (~2 GB of memory)."""
import sys

content = b"BT /F1 400 Tf 1000 7000 Td (Riesenseite) Tj ET"
objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 14400 14400] "
    b"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
    b"<< /Length %d >>\nstream\n%s\nendstream" % (len(content), content),
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
]

out = bytearray(b"%PDF-1.7\n")
offsets = [0]
for i, body in enumerate(objects, start=1):
    offsets.append(len(out))
    out += b"%d 0 obj\n%s\nendobj\n" % (i, body)
xref_pos = len(out)
out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
out += b"".join(b"%010d 00000 n \n" % off for off in offsets[1:])
out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref_pos)

with open(sys.argv[1], "wb") as f:
    f.write(out)
print(f"wrote {sys.argv[1]} ({len(out)} bytes)")
