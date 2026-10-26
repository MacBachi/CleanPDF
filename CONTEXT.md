# CleanPDF — Kontext

macOS-App (SwiftUI, Swift Package) zum Entschärfen nicht vertrauenswürdiger
PDFs durch Rasterisierung in einem abgeschotteten Hilfsprozess.
Sicherheitsmodell und Benutzung: siehe README.md und SECURITY.md.

Repo: https://github.com/MacBachi/CleanPDF · Lizenz: GPLv3 (Header in allen
Quelldateien) · Arbeitsverzeichnis: `/Users/mb/Dev/CleanPDF`.

## Aufbau

- `Sources/CleanPDF/Worker.swift` — Hilfsprozess (dieselbe Binärdatei mit
  `--worker render|analyze`): setzt Ressourcenlimits, lädt die Info.plist vor,
  sperrt sich per SBPL-Profil ein und liest erst dann das PDF von stdin.
  Liefert nur Seitengröße + rohe RGBX-Pixel bzw. den Analysebericht als JSON.
  Enthält auch `--sandbox-selftest`.
- `Sources/CleanPDF/IsolatedPDF.swift` — App-Seite der Grenze: startet Worker,
  füttert die Datei, validiert jede Nachricht, Wächter für Zeit (120 s,
  pausiert während die App selbst an einer Seite arbeitet) und Speicher
  (3 GB). `analyzeReport` macht aus Fehlern einen Befund.
- `Sources/CleanPDF/WorkerProtocol.swift` — binäres Übertragungsformat.
- `Sources/CleanPDF/Sanitizer.swift` — baut das neue PDF aus validierten
  Pixeln (JPEG + optionale unsichtbare OCR-Ebene), `RenderBudget`.
- `Sources/CleanPDF/RiskAnalyzer.swift` — Risiko-Score 0–100 aus Bytes (läuft
  im Worker): strukturelle CGPDF-Probes + Rohdaten-Scan, JBIG2-Hinweis.
- `Sources/CleanPDF/AppUI.swift`, `Main.swift` — GUI bzw. Einstieg
  (Worker → Selbsttest → CLI → GUI).
- `Sources/CleanPDF/HelpContent.swift` / `HelpView.swift` — eingebaute Hilfe
  (Deutsch, „du“): Fenster mit Themen + Suche, Menü „Hilfe“ (⌘?, Direkt-
  einstiege), „?“ im Hauptfenster, Links aus Leerzustand und Risiko-Details.
- `Sources/CIsolation/` — C-Shim für `sandbox_init`, `proc_pid_rusage`,
  `setrlimit`.
- `build-app.sh` — arm64-Bundle (bricht ab, wenn das Binary nicht arm64 ist),
  Icon, ad-hoc-Signatur. Enthält die Bundle-Version.
- `tests/run.sh` — End-to-End-Suite (40 Checks), `tests/make_*` erzeugen die
  Fixtures zur Laufzeit (keine Binär-Assets im Repo), `check_render_parity`
  vergleicht Original und Ausgabe pixelweise bei 200 dpi.
- `tests/CleanPDFTests/` — XCTest (`swift test`), u. a. spielt einen
  kompromittierten Worker gegen die Validierung.
- `.github/workflows/` — `ci.yml` (macos-15, macos-26), `release.yml` (Tag
  `v*`: einmal bauen → genau dieses ZIP auf macos-15 und macos-26 testen →
  veröffentlichen; manueller Start = Probelauf).

## Entscheidungen

- Rasterisierung statt selektivem Filtern: strukturelle Garantie, dass keine
  aktiven Inhalte übernommen werden (Dangerzone-Prinzip).
- Abschottung per Prozess-Sandbox statt VM/Container: kein Unterbau nötig.
  Restrisiko Sandbox-/Kernel-Ausbruch ist dokumentiert.
- `sandbox_init` mit Profiltext statt App Sandbox: deny-default ist deutlich
  strenger (App Sandbox erlaubt viel IPC), und es funktioniert für CLI und
  App gleich. API ist deprecated → fail closed + Selbsttest in jeder CI.
  Getestet: Ein Prozess in einer bestehenden Sandbox (`sandbox-exec`) kann
  keine zweite anwenden → Worker verweigert, keine Ausgabe.
- Profil ohne pauschales `file-read-metadata`: nicht nötig, gemessen an 20
  realen Dokumenten (CJK, Arabisch, Hebräisch, Thai, Bilder, Verläufe) mit
  Pixelparität.
- `prepareForSandbox()`: ImageIO liest beim ersten Bild die Info.plist des
  Hauptprogramms (Entscheidung über Out-of-Process-Dekodierung); in der
  Sandbox stürzt CoreFoundation dabei ab statt sauber zu scheitern → jedes
  JPEG tötete den Worker. Vorab laden behebt das, ohne das Profil zu lockern.
- Nur rohe Pixel über die Grenze: Die App dekodiert nichts, was der Worker
  erzeugt hat; Alpha wird ignoriert; Maße werden vor jeder Multiplikation
  per Double geprüft (sonst Überlauf-Absturz bei UInt32.max²).
- OCR bleibt in der App: Vision braucht Systemdienste und sieht nur unsere
  eigenen, validierten Pixel.
- `RenderBudget` 50 MP / 20 000 px Kante: Eine 600-Byte-Seite mit
  14 400 × 14 400 pt brauchte sonst ~1,9 GB. Seitengröße bleibt erhalten.
- Wächter-Zeitlimit 120 s pro Seite: Eine 1-KB-Datei mit wiederholten
  ganzseitigen Verläufen beschäftigt den Renderer legitim 45 s.
- Speicherwächter misst alle 0,5 s → zielt auf anhaltendes Wachstum
  (Dekompressionsbomben), nicht auf kurze Spitzen.
- OCR mit automatischer Spracherkennung statt fest de/en: gemessen auf zehn
  Seiten in acht Schriften — fest de/en erkannte CJK/Thai/Arabisch kaum
  (~10 %), automatisch 96–99 % bei CJK/Thai ohne Verlust bei Latein/Kyrillisch.
  `RecognizeDocumentsRequest` (macOS 26) geprüft und verworfen: erkannte auf
  normalen Seiten viel weniger Text (z. B. 420 von 2401 Zeichen).
- JBIG2 als Hinweis ohne Punkte: in Scans üblich, kein aktiver Inhalt, aber
  Angriffsweg von FORCEDENTRY.
- Rohdaten-Scan ignoriert `stream…endstream`-Inhalte (Zufallstreffer wie
  `/JS` in JPEG-Daten); Interne Verweise (`/Dest`, `GoTo`) zählen 0 Punkte.
- Paritätsvergleich bei 200 dpi statt 72: Bei niedriger Auflösung glätten
  Vektorkanten anders als verkleinerte Bitmaps → falsche Abweichungen bei
  kleiner Schrift und Icons.
- Swift-Tools-Version bleibt 5.9 (Swift-5-Sprachmodus); getestet wird mit
  Swift 6.1+ — ältere Toolchains sind nicht mehr verifiziert.
- CI-Runner: macos-14 wurde am 2. 11. 2026 abgeschaltet; Actions auf Node-24-
  Versionen (checkout v7, action-gh-release v3, upload/download-artifact).
- Nur Apple Silicon (Entscheidung vom 25. 10. 2026): Intel wird nicht
  unterstützt. v1.1.0 war die letzte universelle Version, ab v1.2.0 arm64.
- Veröffentlichte Tags werden nicht verschoben (v1.0.0 → v1.0.1 statt Umhängen).
- Release-Tags werden signiert (SSH-Schlüssel aus 1Password, wie v1.0.x und
  v1.1.0). Ohne entsperrtes 1Password wird nichts unsigniert veröffentlicht.
- Hilfe als eigenes SwiftUI-Fenster statt Apple-Help-Book: Help Viewer ist
  bei ad-hoc-signierten Apps unzuverlässig, das Fenster ist testbar. Zahlen
  (Zeitlimit, Speicher, Megapixel, Score-Stufen, Punkte) kommen aus den
  Konstanten im Code; Tests rendern jede Seite hell/dunkel per ImageRenderer.
- Bundle-Sprache Deutsch (`CFBundleDevelopmentRegion de`): Die Oberfläche ist
  deutsch; ohne die Angabe zeigte macOS die Standardmenüs englisch.
- `--sandbox-selftest` verlangt existierende Datei und Ordner: Eine fehlende
  Datei schlägt auch ohne Sandbox fehl und wurde als „blocked“ gewertet.
- Unit-Tests liegen in `tests/CleanPDFTests` (klein): macOS-Dateisystem
  unterscheidet keine Groß-/Kleinschreibung, `Tests/` landete im vorhandenen
  `tests/`; Package.swift nennt den echten Pfad.
