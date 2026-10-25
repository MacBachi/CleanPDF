# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] — 2026-10-25

### Security
- **Untrusted PDFs are now parsed, rendered and analysed only in a sandboxed
  worker process.** It locks itself into a deny-default sandbox profile
  before reading the file: no network or DNS, no access to user files, no
  writing, no launching processes, no IPC to system services. It can return
  only page sizes and raw pixels, which the app validates before use. If the
  sandbox cannot be applied, the file is not processed (fail closed).
- Watchdog: a worker is killed after 120 s without progress on a page or
  above 3 GB of memory (tunable via `CLEANPDF_PAGE_TIMEOUT` and
  `CLEANPDF_WORKER_MEMORY_MB`); it also exits when the app goes away.
- Render budget of 50 megapixels per page: a ~600-byte PDF declaring a
  maximum-size page no longer makes CleanPDF allocate ~2 GB. Oversized pages
  are rendered at a reduced resolution and reported.
- The risk analysis notes image data in the JBIG2 format (the decoder used by
  the FORCEDENTRY exploit) — informational, no score.

### Added
- `CleanPDF --sandbox-selftest <file> <dir>` verifies the isolation on the
  local machine.
- Universal binary: the release now really runs on Intel Macs (1.0.x was
  arm64-only despite the README).

### Changed
- OCR detects the language per page instead of assuming German/English.
  Korean, Chinese, Japanese and Thai pages are now searchable (measured
  96–99 % of characters, previously ~10 %).
- OCR lines are separated in copied/searched text instead of running together.

### Fixed
- CI moved off the retired macos-14 runner image; actions updated to their
  Node 24 versions.

### Infrastructure
- CI matrix: macos-15, macos-26 and macos-15-intel.
- Release pipeline builds once, tests that exact artifact on Intel and Apple
  silicon, then publishes; manual runs are dry runs.
- New tests: XCTest unit tests acting as a compromised worker against the
  app's validation; end-to-end checks for sandbox enforcement (with control
  runs), fail-closed behaviour, pixel parity for fonts/JPEG/JPEG 2000/ICC/
  shadings/transparency, timeout and memory watchdog, render budget, and
  multilingual OCR — 39 end-to-end checks in total.

## [1.0.1] — 2026-08-25

### Fixed
- Package now builds on the Swift 5.10 toolchain used by GitHub's macOS
  runners (lowered `swift-tools-version`, removed a concurrency error from
  capturing a mutated `var` in a detached task). No user-visible behaviour
  change; this makes CI and the automated release pipeline work.
- App bundle version string is now `1.0.0`-style semantic versioning.

## [1.0.0] — 2026-08-25

Initial public release.

### Added
- Rasterise-and-rebuild PDF sanitisation: every page is rendered to an image
  and a brand-new PDF is built, so no active content from the source survives.
- Guaranteed removal of JavaScript, auto-run actions, external links/canaries,
  embedded files, forms, multimedia, signatures/certificates, and metadata.
- Optional invisible OCR text layer (Apple Vision, on-device) keeping output
  searchable and selectable.
- Risk score (0–100) with detailed findings: structural analysis of the parsed
  PDF plus a raw-byte safety net; shows actual JavaScript code and external URLs.
- Post-sanitisation self-verification ("output verified" only at score 0).
- SwiftUI app with drag & drop, batch queue, resolution and OCR options.
- Command-line mode, including `--scan` for analysis-only with a scripting-
  friendly exit code.
- End-to-end test suite (`tests/run.sh`) and GitHub Actions CI.

### Notes
- App is ad-hoc signed, not notarised; first launch requires right-click → Open.
