# CleanPDF — Kontext

macOS-App (SwiftUI, Swift Package) zum Entschärfen nicht vertrauenswürdiger
PDFs durch Rasterisierung. Sicherheitsmodell und Benutzung: siehe README.md.

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
- `Sources/CleanPDF/Main.swift` — Einstieg; mit Dateiargumenten CLI-Modus,
  ohne Argumente GUI.
- `build-app.sh` — baut `build/CleanPDF.app` (SPM-Binary + Info.plist,
  App-Icon aus `assets/AppIcon.png` via sips/iconutil, ad-hoc-signiert).
- `assets/` — App-Icon-PNG (1024²) und `generate_icon.swift`, das das Icon
  programmatisch nachzeichnet; eine eigene PNG an gleicher Stelle gewinnt.
- `tests/` — Erzeugung eines bösartigen Test-PDFs und Verifikations-Scan.

## Entscheidungen

- Rasterisierung statt selektivem Filtern: strukturelle Garantie, dass keine
  aktiven Inhalte übernommen werden (Dangerzone-Prinzip, lokal ohne Container).
- Kein App Sandbox vorerst: Ausgabe soll neben der Eingabedatei liegen;
  Sandbox würde dafür Save-Panels pro Datei erzwingen.
- Sprachmodus Swift 5 (`swiftLanguageMode(.v5)`) um Strict-Concurrency-Reibung
  mit CoreGraphics-Typen zu vermeiden.
