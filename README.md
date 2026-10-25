<div align="center">

# CleanPDF

**Turn untrusted PDFs into guaranteed-passive, safe PDFs — on your Mac, offline.**

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20·%20Apple%20silicon%20%2B%20Intel-lightgrey.svg)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-6.1%2B-orange.svg)](https://swift.org)
[![CI](https://github.com/MacBachi/CleanPDF/actions/workflows/ci.yml/badge.svg)](https://github.com/MacBachi/CleanPDF/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/MacBachi/CleanPDF?include_prereleases&sort=semver)](https://github.com/MacBachi/CleanPDF/releases/latest)

<img src="assets/AppIcon.png" width="160" alt="CleanPDF icon">

</div>

CleanPDF takes a PDF you don't trust and produces a new PDF that is
**guaranteed to contain no active content** — no JavaScript, no external
links or tracking "canaries", no embedded/attached files, no forms, no digital
signatures or certificates. Just the pages, as pixels your Mac rendered itself.

The untrusted file is only ever opened inside a **locked-down sandbox process**
that cannot reach the network, your files, or other programs — so even a PDF
built to exploit the PDF engine has nowhere to go.

It also shows you a **risk score with full details** of what the original file
contained, so you can see exactly what was neutralised.

Everything runs **locally and offline**. No file ever leaves your machine.

---

## How it works

CleanPDF does **not** try to filter dangerous parts out of a PDF (that is
error-prone — PDFs can hide content in countless places). Instead it
**rasterises** the document and rebuilds it from scratch, and it keeps the
untrusted file away from everything that matters while doing so:

```
 untrusted.pdf ──stdin──▶ ┌──────────────── sandboxed worker ───────────────┐
                          │ parse + render each page with CoreGraphics      │
                          │ no network · no DNS · no file access · no exec  │
                          └───────────────┬─────────────────────────────────┘
                        page size + raw pixels only (validated by the app)
                                          ▼
                          ┌──────────────── CleanPDF app ───────────────────┐
                          │ build a brand-new PDF: JPEG page images         │
                          │ + optional invisible on-device OCR text layer   │
                          └───────────────┬─────────────────────────────────┘
                                          ▼
                                  untrusted (safe).pdf
```

1. **Isolated rendering.** A child process (the same app binary) first locks
   itself into a deny-everything macOS sandbox profile — it may only read
   macOS system files such as frameworks, fonts and colour profiles — and
   only then receives the PDF.
   It parses and renders each page and sends back nothing but the page size
   and raw pixels. If the sandbox cannot be applied, it refuses to work.
2. **Strict boundary.** The app treats everything from the worker as hostile:
   page order, sizes and pixel budget are checked, the byte count must match
   exactly, and transparency is ignored. A watchdog kills the worker if a page
   stalls (120 s) or it uses too much memory (3 GB).
3. **Fresh PDF.** The app builds a new PDF from the validated pixels. It
   contains only JPEG page images plus, optionally, an invisible OCR text
   layer (Apple Vision, on-device). **Nothing** from the source file's object
   structure is carried over.

This is the principle of [Dangerzone](https://dangerzone.rocks), applied
natively on macOS with a process sandbox instead of a container.

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

Every file you add is analysed immediately — inside the same sandbox, without
rendering it — and gets a 0–100 score with a colour badge; click it for
details. The analysis is two-layered:

1. **Structural** — a targeted walk of the parsed PDF object tree: auto-run
   actions, JavaScript (with the actual code shown), external URLs (each one
   listed), attachments (with filenames), forms, multimedia, signatures. This
   also sees content inside compressed object streams.
2. **Raw-byte scan** as a safety net for malformed or obfuscated files. Stream
   contents (images, compressed data) are excluded so random bytes in a JPEG
   don't cause false positives.

Internal links (tables of contents, "continued on page X") are recognised as
navigation and scored 0 — only real external URLs count. Image data in the
JBIG2 format is listed as a note (no score): it is common in scans, but its
decoder was the attack path of the FORCEDENTRY exploit.

> **Score 0 means "no known active elements found", not "guaranteed harmless".**
> The guarantee comes from the rasterisation, which always rebuilds everything
> regardless of the score.

## Install

### Download (recommended)

Grab the latest `CleanPDF.app` from the
[**Releases**](https://github.com/MacBachi/CleanPDF/releases/latest) page,
unzip, and drag it to `/Applications`. It is a universal app (Apple silicon
and Intel); every release is tested on both before it is published.

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

Requires Swift 6.1 or newer (Xcode 16.3+) on macOS 14 or newer. CI builds and
tests with Swift 6.1 and 6.3, on Apple silicon and on Intel.

## Usage

**App:** drag PDFs onto the window (or the Dock icon). The result is written
next to the original as `<name> (safe).pdf`. You can choose resolution
(150 / 200 / 300 dpi) and toggle the searchable OCR layer.

**Command line** (same binary inside the bundle, or `.build/release/CleanPDF`):

```bash
CleanPDF [--scan] [--dpi N] [--no-ocr] [--output <dir>] file.pdf [more.pdf ...]
CleanPDF --sandbox-selftest <file-to-read> <dir-to-write>
```

- `--scan` — only print the risk analysis, don't sanitise. Exit code
  `0` = unremarkable, `1` = findings. Handy in scripts.
- `--dpi N` — render resolution (72–600, default 200).
- `--no-ocr` — skip the invisible OCR text layer.
- `--output <dir>` — write results into a directory instead of next to inputs.
- `--sandbox-selftest` — enters the worker sandbox and checks on *your*
  machine that reading the given file, writing into the given directory,
  network, DNS and starting programs are all blocked.

Tuning (environment variables): `CLEANPDF_PAGE_TIMEOUT` (seconds a page may
take, default 120) and `CLEANPDF_WORKER_MEMORY_MB` (worker memory ceiling,
default 3072).

## Requirements

- macOS 14 (Sonoma) or newer
- Apple silicon or Intel (universal binary)

OCR uses Apple's Vision framework, detects the language per page and runs
entirely on-device.

## Limitations (honest)

- **Isolation is a process sandbox, not a VM.** A PDF that exploits the PDF
  engine *and* then escapes the macOS sandbox (a kernel-level exploit) is
  out of scope; for that threat model, run conversion in a VM as Dangerzone
  does. The sandbox is applied with `sandbox_init`, an API Apple marks as
  deprecated but still ships; if it ever stops working, CleanPDF refuses to
  process files rather than run unprotected, and the test suite checks on
  every build that the sandbox is really enforced.
- Oversized pages are rendered within a budget of 50 megapixels per page
  (DIN A2 at 300 dpi fits); larger pages get a lower resolution, which the
  app reports. Their size in points is preserved.
- A page that takes longer than 120 s to render is aborted (a 1 KB PDF can
  legitimately keep a renderer busy for minutes).
- Password-protected PDFs must be unlocked first.
- Output is image-based: vector text becomes pixels (invisible at 200–300 dpi)
  and files can get larger.
- OCR quality was measured on Latin, Cyrillic, Chinese, Japanese, Korean and
  Thai text (96–99 % of characters); Arabic and Hebrew recognition in Apple
  Vision is still weak.
- Printed URLs stay readable as image/OCR text — but they are no longer
  clickable and trigger nothing.
- The two occurrences of `http://www.iec.ch` in output files are the
  description string of the standard sRGB ICC colour profile — passive
  metadata, not a link.

## Testing

```bash
swift test        # unit tests
./tests/run.sh    # end-to-end suite
```

- **Unit tests** play a compromised worker: crafted bytes are pushed through
  a real pipe into the app's validation (out-of-budget sizes, NaN, wrong page
  order, truncated data, oversized messages) — plus the render budget and
  report handling.
- **End-to-end suite** (39 checks): hostile-PDF detection, false-positive
  guards, sanitisation with an independent deep scan of the output, that the
  sandbox blocks file access, network, DNS and process launch (each with a
  control run proving the operation works outside it), that processing is
  refused without the sandbox, pixel-level parity between original and output
  for fixtures with embedded fonts, JPEG, JPEG 2000, ICC colour, gradients and
  transparency, the render budget, the timeout and memory watchdog, and the
  multilingual OCR layer.

## Contributing

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) and, for
security issues, [SECURITY.md](SECURITY.md).

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
Seite als Bild gerendert und daraus ein komplett neues PDF gebaut. Aus der
Struktur des Originals wird nichts übernommen — aktive Inhalte sind damit
strukturell unmöglich. Optional legt lokale OCR (Apple Vision, Sprache wird je
Seite erkannt) eine unsichtbare, durchsuchbare Textebene darüber.

**Abschottung:** Die nicht vertrauenswürdige Datei wird ausschließlich in einem
eigenen Prozess geöffnet, der sich vorher in eine strenge macOS-Sandbox sperrt:
kein Netz, kein DNS, kein Zugriff auf deine Dateien, keine Programmstarts. Er
liefert nur Seitengröße und Pixel zurück, die die App streng prüft. Ohne Sandbox
verweigert er die Arbeit. `CleanPDF --sandbox-selftest` prüft das auf deinem Mac.

**Risiko-Score:** Jede Datei wird sofort analysiert (0–100) und zeigt im Detail,
was das Original enthielt — inklusive gefundener URLs und JavaScript-Code.

**Installieren:** Fertige App (Apple Silicon und Intel) unter
[Releases](https://github.com/MacBachi/CleanPDF/releases/latest) laden, oder
selbst bauen mit `./build-app.sh`. Die App ist ad-hoc signiert, nicht notarisiert
— beim ersten Start per Rechtsklick → Öffnen starten.

**Benutzung:** PDF ins Fenster ziehen; Ergebnis landet als `<Name> (safe).pdf`
daneben. Kommandozeile: `CleanPDF [--scan] [--dpi N] [--no-ocr] datei.pdf …`.

**Ehrlicher Hinweis:** Die Abschottung ist eine Prozess-Sandbox, keine VM. Ein
Angriff, der die PDF-Engine *und* zusätzlich den macOS-Kernel überwindet, liegt
außerhalb dessen, wovor CleanPDF schützt — dafür eine VM verwenden.

</details>
