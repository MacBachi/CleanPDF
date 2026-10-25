#!/usr/bin/env python3
"""Builds a 2-page PDF: page 1 is trivial, page 2 paints a full-page radial
shading thousands of times. Each paint touches every pixel of the page, so
rendering takes seconds while the file stays tiny. Fixture for the worker
watchdog (timeout on page 2, partial output must be removed).

With a page size of e.g. 14400 pt, page 2 also holds a ~200 MB bitmap for
the whole render, which makes it the fixture for the worker memory ceiling.

Usage: make_slow_page_pdf.py out.pdf [paints] [page2-size-in-points]"""
import sys
import zlib

count = int(sys.argv[2]) if len(sys.argv) > 2 else 4000
size = int(sys.argv[3]) if len(sys.argv) > 3 else 0
box2 = b"0 0 %d %d" % (size, size) if size else b"0 0 612 792"
center = size // 2 if size else 396
heavy = zlib.compress(b"q\n" + b"/Sh0 sh\n" * count + b"Q\n", 9)
light = b"BT /F1 24 Tf 72 700 Td (Seite 1) Tj ET"

objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 5 0 R "
    b"/Resources << /Font << /F1 7 0 R >> >> >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [%s] /Contents 6 0 R " % box2 +
    b"/Resources << /Shading << /Sh0 << /ShadingType 3 /ColorSpace /DeviceRGB "
    b"/Coords [%d %d 0 %d %d 500] /Extend [true true] " % (center, center, center, center) +
    b"/Function << /FunctionType 2 /Domain [0 1] /C0 [1 1 0] /C1 [0 0 1] /N 1 >> >> >> >> >>",
    b"<< /Length %d >>\nstream\n%s\nendstream" % (len(light), light),
    b"<< /Length %d /Filter /FlateDecode >>\nstream\n%s\nendstream" % (len(heavy), heavy),
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
print(f"wrote {sys.argv[1]} ({len(out)} bytes, {count} full-page shadings on page 2)")
