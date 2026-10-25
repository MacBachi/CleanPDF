# Contributing to CleanPDF

Thanks for your interest in improving CleanPDF! This is a small, focused tool
with one job: turning untrusted PDFs into guaranteed-passive ones. Contributions
that keep it simple, safe, and honest are very welcome.

## Getting started

```bash
git clone https://github.com/MacBachi/CleanPDF.git
cd CleanPDF
swift build            # debug build
swift test             # unit tests
./tests/run.sh         # end-to-end test suite
./build-app.sh         # CleanPDF.app bundle (arm64)
```

You need Swift 6.1 or newer (Xcode 16.3+) on macOS 14 or newer. CI runs on
the oldest and newest supported GitHub macOS images (Swift 6.1 and 6.3), so
please keep the code building there. CleanPDF targets Apple silicon only.
The end-to-end suite
also uses Python 3, `sips` and `sandbox-exec`, all of which ship with macOS.

## Project layout

| Path | What it is |
|---|---|
| `Sources/CleanPDF/Worker.swift` | The sandboxed worker: sandbox profile, page rendering, analysis, `--sandbox-selftest` |
| `Sources/CleanPDF/IsolatedPDF.swift` | App side of the boundary: starts workers, validates everything they send, watchdog |
| `Sources/CleanPDF/WorkerProtocol.swift` | Binary wire format between worker and app |
| `Sources/CleanPDF/Sanitizer.swift` | Builds the new PDF from validated pixels; render budget; OCR layer |
| `Sources/CleanPDF/RiskAnalyzer.swift` | Risk score (structural probes + raw-byte safety net); runs inside the worker |
| `Sources/CleanPDF/AppUI.swift` | SwiftUI GUI, job queue, risk badges |
| `Sources/CleanPDF/HelpContent.swift` | In-app help text (German); numbers come from the code's constants |
| `Sources/CleanPDF/HelpView.swift` | Help window, Help menu, deep links into help |
| `Sources/CleanPDF/Main.swift` | Entry point: worker, self-test, CLI or GUI |
| `Sources/CIsolation/` | Small C shim for `sandbox_init`, process memory and resource limits |
| `build-app.sh` | Builds the arm64, ad-hoc signed `.app` bundle with icon |
| `assets/generate_icon.swift` | Regenerates the app icon programmatically |
| `tests/CleanPDFTests/` | XCTest unit tests (`swift test`) |
| `tests/run.sh` | End-to-end suite; `tests/make_*` generate its fixtures |

## Guidelines

- **Never parse an untrusted PDF outside the worker.** No `CGPDFDocument`,
  `PDFDocument` or similar on user input in the app process — route it
  through `IsolatedPDF`. The app may only handle validated pixels.
- **Never weaken the output guarantee.** The output must stay a
  rasterise-and-rebuild — don't add code paths that copy structure from the
  untrusted source into the output.
- **Loosen the sandbox profile only with evidence.** If a sandbox rule breaks
  rendering, show it with a failing parity test or sandbox log, allow the
  narrowest path that fixes it, and say why in a comment.
- **Add a test** for any behaviour change. `swift test` and `tests/run.sh`
  must stay green. A test that can't fail proves nothing — check new tests
  against a deliberately broken build once.
- **Be honest in the UI and docs.** If something is a heuristic (like the risk
  score), say so; don't imply a guarantee the code doesn't provide.
- **Keep the in-app help in step.** When behaviour changes, update
  `HelpContent.swift`; quote limits through the code's constants, never as
  typed-in numbers.
- Match the existing code style. Keep comments about *why*, not *what*.

## Submitting changes

1. Fork and create a feature branch.
2. Make your change; run `swift test` and `./tests/run.sh`.
3. Open a pull request describing what and why.

By contributing, you agree that your contributions are licensed under the
project's [GPLv3](LICENSE).

## Releases

Push a signed `vX.Y.Z` tag. The release workflow builds the app once, runs
the full test suite against that exact zip on the oldest and newest supported
macOS image, and only then publishes it. Running the workflow manually is a dry run that skips
publishing. Keep the bundle version in `build-app.sh` and `CHANGELOG.md` in
step with the tag.

## Reporting security issues

See [SECURITY.md](SECURITY.md).
