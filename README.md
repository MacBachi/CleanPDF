<div align="center">

# CleanPDF

**Turn untrusted PDFs into guaranteed-passive, safe PDFs — on your Mac, offline.**

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![CI](https://github.com/MacBachi/CleanPDF/actions/workflows/ci.yml/badge.svg)](https://github.com/MacBachi/CleanPDF/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/MacBachi/CleanPDF?include_prereleases&sort=semver)](https://github.com/MacBachi/CleanPDF/releases/latest)

<img src="assets/AppIcon.png" width="160" alt="CleanPDF icon">

</div>

CleanPDF takes a PDF you don't trust and produces a new PDF that is
**guaranteed to contain no active content** — no JavaScript, no external
links or tracking "canaries", no embedded/attached files, no forms, no digital
signatures or certificates. Just the pages, as pixels your Mac rendered itself.

It also shows you a **risk score with full details** of what the original file
contained, so you can see exactly what was neutralised.

Everything runs **locally and offline**. No file ever leaves your machine.

---

## How it works

CleanPDF does **not** try to filter dangerous parts out of a PDF (that is
error-prone — PDFs can hide content in countless places). Instead it
**rasterises** the document:

1. Every page is rendered to an image with CoreGraphics (`CGPDFDocument`) — a
   pure rasteriser that executes no scripts and makes no network connections.
2. A **brand-new PDF** is built from those images. It contains only JPEG page
   images plus, optionally, an invisible on-device-OCR text layer. **Nothing**
   from the source file's object structure is carried over.

This is the same principle as [Dangerzone](https://dangerzone.rocks), applied
natively on macOS without a container.

The result structurally cannot contain:

| Threat | PDF mechanism |
|---|---|
| JavaScript | `/JavaScript`, `/JS` |
| Auto-run actions | `/OpenAction`, `/AA`, `/Launch` |
| External links / canaries | `/URI`, `/GoToR`, `/SubmitForm`, `/ImportData` |
| Embedded / attached files | `/EmbeddedFile`, `/Filespec` |
| Forms | `/AcroForm`, XFA |
| Multimedia | `/RichMedia`, `/Movie`, `/Sound` |
| Signatures & certificates | `/Sig`, `/ByteRange`, `/Cert` |
| Annotations & original metadata | all of it |

After sanitising, CleanPDF **re-analyses its own output** and only shows
"output verified" when the score is 0.

## Risk score

Every file you add is analysed immediately (without rendering it) and gets a
0–100 score with a colour badge; click it for details. The analysis is
two-layered:

1. **Structural** — a targeted walk of the parsed PDF object tree: auto-run
   actions, JavaScript (with the actual code shown), external URLs (each one
   listed), attachments (with filenames), forms, multimedia, signatures. This
   also sees content inside compressed object streams.
2. **Raw-byte scan** as a safety net for malformed or obfuscated files. Stream
   contents (images, compressed data) are excluded so random bytes in a JPEG
   don't cause false positives.

Internal links (tables of contents, "continued on page X") are recognised as
navigation and scored 0 — only real external URLs count.

> **Score 0 means "no known active elements found", not "guaranteed harmless".**
> The guarantee comes from the rasterisation, which always rebuilds everything
> regardless of the score.

## Install

### Download (recommended)

Grab the latest `CleanPDF.app` from the
[**Releases**](https://github.com/MacBachi/CleanPDF/releases/latest) page,
unzip, and drag it to `/Applications`.

The app is **ad-hoc signed, not notarised** (this is a free, unfunded
project). On first launch macOS Gatekeeper will block it; open it once via
**right-click → Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/CleanPDF.app
```

### Build from source

```bash
git clone https://github.com/MacBachi/CleanPDF.git
cd CleanPDF
./build-app.sh
cp -R build/CleanPDF.app /Applications/
```

Requires a Swift 5.9 or newer toolchain (Xcode 15+) on macOS 14 or newer.
CI builds with Swift 5.10; development happens on Swift 6.x — both work.

## Usage

**App:** drag PDFs onto the window (or the Dock icon). The result is written
next to the original as `<name> (safe).pdf`. You can choose resolution
(150 / 200 / 300 dpi) and toggle the searchable OCR layer.

**Command line** (same binary inside the bundle, or `.build/release/CleanPDF`):

```bash
CleanPDF [--scan] [--dpi N] [--no-ocr] [--output <dir>] file.pdf [more.pdf ...]
```

- `--scan` — only print the risk analysis, don't sanitise. Exit code
  `0` = unremarkable, `1` = findings. Handy in scripts.
- `--dpi N` — render resolution (72–600, default 200).
- `--no-ocr` — skip the invisible OCR text layer.
- `--output <dir>` — write results into a directory instead of next to inputs.

## Requirements

- macOS 14 (Sonoma) or newer
- Apple silicon or Intel

OCR uses Apple's Vision framework and runs entirely on-device.

## Limitations (honest)

- **The renderer parses the untrusted file.** Conversion itself feeds the PDF
  to CoreGraphics (the same engine as Preview / Quick Look). A zero-day against
  the parser is theoretically possible; for maximum isolation run conversion in
  a VM, as Dangerzone does.
- Password-protected PDFs must be unlocked first.
- Output is image-based: vector text becomes pixels (invisible at 200–300 dpi)
  and files can get larger.
- Printed URLs stay readable as image/OCR text — but they are no longer
  clickable and trigger nothing.
- The two occurrences of `http://www.iec.ch` in output files are the
  description string of the standard sRGB ICC colour profile — passive
  metadata, not a link.

## Testing

```bash
./tests/run.sh
```

Builds the release binary and runs an end-to-end suite: hostile-PDF detection,
the binary-stream false-positive guard, sanitisation, an independent deep
marker scan of the output, and a rendering-geometry regression check.

## Contributing

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[GNU General Public License v3.0](LICENSE) © CleanPDF contributors.

CleanPDF is free software: you can redistribute it and/or modify it under the
terms of the GPL, either version 3 of the License, or (at your option) any
later version.

---

<details>
<summary><b>🇩🇪 Deutsche Kurzfassung</b></summary>

<br>

**CleanPDF** wandelt nicht vertrauenswürdige PDFs in garantiert passive, sichere
PDFs um — lokal auf deinem Mac, offline. Kein JavaScript, keine externen
Links/Canaries, keine eingebetteten Dateien, keine Formulare, keine Signaturen.

**Prinzip:** Statt gefährliche Teile herauszufiltern (fehleranfällig), wird jede
Seite mit CoreGraphics als Bild gerendert und daraus ein komplett neues PDF
gebaut. Aus der Struktur des Originals wird nichts übernommen — aktive Inhalte
sind damit strukturell unmöglich. Optional legt lokale OCR (Apple Vision) eine
unsichtbare, durchsuchbare Textebene darüber. Nach der Bereinigung prüft die App
ihre eigene Ausgabe erneut.

**Risiko-Score:** Jede Datei wird sofort analysiert (0–100) und zeigt im Detail,
was das Original enthielt — inklusive gefundener URLs und JavaScript-Code.

**Installieren:** Fertige App unter
[Releases](https://github.com/MacBachi/CleanPDF/releases/latest) laden, oder
selbst bauen mit `./build-app.sh`. Die App ist ad-hoc signiert, nicht notarisiert
— beim ersten Start per Rechtsklick → Öffnen starten.

**Benutzung:** PDF ins Fenster ziehen; Ergebnis landet als `<Name> (safe).pdf`
daneben. Kommandozeile: `CleanPDF [--scan] [--dpi N] [--no-ocr] datei.pdf …`.

**Ehrlicher Hinweis:** Die Umwandlung selbst parst das PDF mit CoreGraphics
(wie Vorschau). Für maximale Isolation eine VM verwenden (Dangerzone-Prinzip).

</details>
