# CleanPDF — Kontext

macOS-App (SwiftUI, Swift Package) zum Entschärfen nicht vertrauenswürdiger
PDFs durch Rasterisierung. Sicherheitsmodell und Benutzung: siehe README.md.

Repo: https://github.com/MacBachi/CleanPDF · Lizenz: GPLv3 (Header in allen
Quelldateien) · Arbeitsverzeichnis: `/Users/mb/Dev/CleanPDF`.

## Aufbau

- `Sources/CleanPDF/Sanitizer.swift` — Kern: CGPDFDocument-Rendering pro Seite
  → JPEG-Bild → neues PDF via CGContext; optional unsichtbare OCR-Textebene
  (Vision + CoreText, Modus `.invisible`).
- `Sources/CleanPDF/RiskAnalyzer.swift` — Risiko-Score 0–100 ohne Rendering:
  strukturelle CGPDF-Probes (OpenAction/AA/Names/AcroForm/Annots/Aktionen)
  plus Rohdaten-Marker-Scan als Sicherheitsnetz. Läuft beim Hinzufügen auf
  das Original und nach der Bereinigung als Verifikation auf die Ausgabe.
- `Sources/CleanPDF/AppUI.swift` — SwiftUI-GUI (Drag & Drop, Job-Queue,
  DPI/OCR-Einstellungen, Risiko-Badge mit Detail-Ausklapp, „Ausgabe geprüft"),
  `JobQueue.outputURL` benennt `<Name> (safe).pdf`.
- `Sources/CleanPDF/Main.swift` — Einstieg; mit Dateiargumenten CLI-Modus
  (inkl. `--scan`), ohne Argumente GUI.
- `build-app.sh` — baut `build/CleanPDF.app` (SPM-Binary + Info.plist,
  App-Icon aus `assets/AppIcon.png` via sips/iconutil, ad-hoc-signiert).
  Enthält die Bundle-Version — bei einem Release mit dem Tag angleichen.
- `assets/` — App-Icon-PNG (1024²) und `generate_icon.swift`, das das Icon
  programmatisch zeichnet; eine eigene PNG an gleicher Stelle gewinnt.
- `tests/` — `run.sh` ist die End-to-End-Suite (10 Checks); die
  `make_*.py`-Skripte erzeugen Fixtures (bösartiges PDF, Binärstream-PDF),
  `verify_clean.py` scannt eine Ausgabe unabhängig auf 26 Aktiv-Marker,
  `check_geometry.swift` sichert gegen die Seitengeometrie-Regression ab.
- `.github/workflows/` — `ci.yml` (Push/PR: Build, Tests, App-Bundle),
  `release.yml` (Tag `v*`: baut, testet, hängt ZIP + SHA-256 ans Release).

## Entscheidungen

- Rasterisierung statt selektivem Filtern: strukturelle Garantie, dass keine
  aktiven Inhalte übernommen werden (Dangerzone-Prinzip, lokal ohne Container).
- Kein App Sandbox vorerst: Ausgabe soll neben der Eingabedatei liegen;
  Sandbox würde dafür Save-Panels pro Datei erzwingen.
- `swift-tools-version: 5.9` statt 6.0: GitHubs macOS-Runner liefern Swift
  5.10 und können 6.0 nicht lesen. Swift-5-Sprachmodus ist dort ohnehin
  Standard, deshalb entfiel das explizite `swiftLanguageMode(.v5)`. Folge:
  Code muss unter 5.10 kompilieren (z. B. keine mutierte `var` in eine
  detached Task fangen).
- Rohdaten-Scan ignoriert `stream…endstream`-Inhalte: In JPEG-Bilddaten
  kommen kurze Marker wie `/JS` zufällig vor und erzeugten Fehlalarme.
  Verschleiertes bleibt abgedeckt, weil die Struktur-Analyse komprimierte
  Objekt-Streams geparst durchsucht.
- Interne Verweise (`/Dest`, `GoTo`) zählen 0 Punkte: Inhaltsverzeichnisse
  sind keine Bedrohung; nur echte URL-Aktionen gelten als extern.
- Veröffentlichte Tags werden nicht verschoben: v1.0.0 zeigte auf einen
  Stand, der in CI nicht baut, deshalb kam v1.0.1 aus dem geprüften Stand.
