# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
