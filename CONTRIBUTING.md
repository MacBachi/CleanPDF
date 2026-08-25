# Contributing to CleanPDF

Thanks for your interest in improving CleanPDF! This is a small, focused tool
with one job: turning untrusted PDFs into guaranteed-passive ones. Contributions
that keep it simple, safe, and honest are very welcome.

## Getting started

```bash
git clone https://github.com/MacBachi/CleanPDF.git
cd CleanPDF
swift build            # debug build
./build-app.sh         # full CleanPDF.app bundle
./tests/run.sh         # end-to-end test suite
```

You need Xcode 16+ (a Swift 6 toolchain) on macOS 14 or newer. The test suite
additionally uses Python 3, which ships with macOS.

## Project layout

| Path | What it is |
|---|---|
| `Sources/CleanPDF/Sanitizer.swift` | Core: render each page → JPEG → new PDF, optional invisible OCR layer |
| `Sources/CleanPDF/RiskAnalyzer.swift` | Risk score (structural probes + raw-byte safety net) |
| `Sources/CleanPDF/AppUI.swift` | SwiftUI GUI, job queue, risk badges |
| `Sources/CleanPDF/Main.swift` | Entry point; CLI when given file args, GUI otherwise |
| `build-app.sh` | Builds the signed `.app` bundle with icon |
| `assets/generate_icon.swift` | Regenerates the app icon programmatically |
| `tests/` | Fixture generators + `run.sh` end-to-end suite |

## Guidelines

- **Never weaken the safety guarantee.** The output must stay a
  rasterise-and-rebuild — don't add code paths that copy structure from the
  untrusted source into the output.
- **Add a test** for any behaviour change in the sanitizer or analyzer.
  `tests/run.sh` must stay green.
- **Be honest in the UI and docs.** If something is a heuristic (like the risk
  score), say so; don't imply a guarantee the code doesn't provide.
- Match the existing code style. Keep comments about *why*, not *what*.

## Submitting changes

1. Fork and create a feature branch.
2. Make your change; run `./tests/run.sh`.
3. Open a pull request describing what and why.

By contributing, you agree that your contributions are licensed under the
project's [GPLv3](LICENSE).

## Reporting security issues

If you find a way for active content to survive sanitisation, please open an
issue (or, if you consider it sensitive, contact the maintainer privately
first). A reproducer PDF is worth a thousand words — `tests/make_evil_pdf.py`
is a good template.
