#!/usr/bin/env python3
"""Verifies a sanitized PDF: decompresses every stream and scans the whole
object structure for any active-content markers."""
import re
import sys
import zlib

path = sys.argv[1]
raw = open(path, "rb").read()

# Decompress all FlateDecode streams so nothing hides inside compression.
decompressed = b""
for m in re.finditer(rb"stream\r?\n", raw):
    start = m.end()
    end = raw.find(b"endstream", start)
    if end == -1:
        continue
    chunk = raw[start:end]
    try:
        decompressed += zlib.decompress(chunk)
    except zlib.error:
        decompressed += chunk  # not flate (e.g. JPEG) — scan as-is

blob = raw + b"\n" + decompressed
# The standard sRGB ICC profile contains the passive description string
# "IEC http://www.iec.ch" — not a link, just profile metadata. Exempt it.
blob = blob.replace(b"IEC http://www.iec.ch", b"IEC [icc-profile-desc]")

markers = [
    b"/JavaScript", b"/JS", b"/OpenAction", b"/AA", b"/Launch",
    b"/URI", b"/GoToR", b"/GoToE", b"/SubmitForm", b"/ImportData",
    b"/EmbeddedFile", b"/Filespec", b"/AcroForm", b"/XFA",
    b"/RichMedia", b"/Movie", b"/Sound", b"/Annot", b"/Link",
    b"/Sig", b"/ByteRange", b"/Cert", b"/DigestMethod",
    b"evil-canary", b"http://", b"https://",
]

bad = []
for marker in markers:
    # Word boundary for PDF names so /JS doesn't match inside unrelated names.
    if marker.startswith(b"/"):
        pattern = re.escape(marker) + rb"(?![A-Za-z0-9])"
    else:
        pattern = re.escape(marker)
    hits = len(re.findall(pattern, blob))
    if hits:
        bad.append((marker.decode(), hits))

if bad:
    print(f"NICHT SAUBER: {path}")
    for name, hits in bad:
        print(f"  {name}: {hits}x")
    sys.exit(1)
print(f"SAUBER: {path} — keiner von {len(markers)} Aktiv-Inhalt-Markern gefunden.")
