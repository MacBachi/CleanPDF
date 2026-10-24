#!/usr/bin/env python3
"""Builds a 3-page PDF for the JBIG2 detector:
  page 1: image XObject with /Filter [/JBIG2Decode] (array form)
  page 2: JBIG2 image nested inside a Form XObject (name form)
  page 3: ordinary /FlateDecode image -> must NOT be reported
The JBIG2 payload is deliberately not a valid bitstream, which also checks
that a broken image doesn't stop sanitization."""
import sys
import zlib

junk = b"\x97JB2\x0d\x0a\x1a\x0a" + bytes(range(64))  # header-ish, not decodable
flate = zlib.compress(b"\x00" * 8)

c1 = b"q 200 0 0 200 100 400 cm /Im1 Do Q BT /F1 18 Tf 72 720 Td (JBIG2 direkt) Tj ET"
c2 = b"q /Fm1 Do Q BT /F1 18 Tf 72 720 Td (JBIG2 in Form) Tj ET"
c3 = b"q 200 0 0 200 100 400 cm /Im3 Do Q BT /F1 18 Tf 72 720 Td (Flate-Bild) Tj ET"
form = b"q 200 0 0 200 100 400 cm /Im2 Do Q"

def stream(d, data):
    return d % len(data) + b"\nstream\n" + data + b"\nendstream"

objects = [
    b"<< /Type /Catalog /Pages 2 0 R >>",                                    # 1
    b"<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>",                 # 2
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 6 0 R "
    b"/Resources << /Font << /F1 12 0 R >> /XObject << /Im1 9 0 R >> >> >>",  # 3
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 7 0 R "
    b"/Resources << /Font << /F1 12 0 R >> /XObject << /Fm1 13 0 R >> >> >>", # 4
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 8 0 R "
    b"/Resources << /Font << /F1 12 0 R >> /XObject << /Im3 11 0 R >> >> >>", # 5
    stream(b"<< /Length %d >>", c1),                                          # 6
    stream(b"<< /Length %d >>", c2),                                          # 7
    stream(b"<< /Length %d >>", c3),                                          # 8
    stream(b"<< /Type /XObject /Subtype /Image /Width 8 /Height 8 /BitsPerComponent 1 "
           b"/ColorSpace /DeviceGray /Filter [/JBIG2Decode] /Length %d >>", junk),  # 9
    stream(b"<< /Type /XObject /Subtype /Image /Width 8 /Height 8 /BitsPerComponent 1 "
           b"/ColorSpace /DeviceGray /Filter /JBIG2Decode /Length %d >>", junk),    # 10
    stream(b"<< /Type /XObject /Subtype /Image /Width 8 /Height 8 /BitsPerComponent 1 "
           b"/ColorSpace /DeviceGray /Filter /FlateDecode /Length %d >>", flate),   # 11
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",                # 12
    stream(b"<< /Type /XObject /Subtype /Form /BBox [0 0 612 792] "
           b"/Resources << /XObject << /Im2 10 0 R >> >> /Length %d >>", form),     # 13
]

out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
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
