// CleanPDF — turn untrusted PDFs into guaranteed-passive, safe PDFs.
// Copyright (C) 2026 CleanPDF contributors
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. This program is distributed WITHOUT ANY WARRANTY; see
// the GNU General Public License <https://www.gnu.org/licenses/> for details.

import Foundation

/// Topics of the in-app help, in sidebar order.
enum HelpTopicID: String, CaseIterable, Identifiable {
    case overview, howItWorks, usage, riskScore, faq, security, commandLine, about
    var id: String { rawValue }
}

/// Building blocks a help page is made of. Strings may use inline Markdown
/// (`**bold**`, `` `code` ``, links).
enum HelpBlock {
    case lead(String)
    case heading(String)
    case paragraph(String)
    case bullets([String])
    case steps([(title: String, text: String)])
    case note(title: String, text: String)
    case warning(title: String, text: String)
    case code(String)
    case question(String, answer: String)
    case pipelineDiagram
    case scoreLevels
    case severityTable
}

struct HelpTopic: Identifiable {
    let id: HelpTopicID
    let title: String
    let symbol: String
    let blocks: [HelpBlock]

    /// Everything on the page as lower-case text, for the search field.
    var searchableText: String {
        let parts: [String] = [title] + blocks.flatMap { block -> [String] in
            switch block {
            case .lead(let s), .heading(let s), .paragraph(let s), .code(let s): return [s]
            case .bullets(let items): return items
            case .steps(let steps): return steps.flatMap { [$0.title, $0.text] }
            case .note(let t, let s), .warning(let t, let s): return [t, s]
            case .question(let q, let a): return [q, a]
            case .pipelineDiagram: return ["Ablauf Sandbox Hilfsprozess Pixel neues PDF"]
            case .scoreLevels: return RiskReport.levelBands.map(\.label)
            case .severityTable:
                return RiskFinding.Severity.allCases.flatMap { [$0.label, HelpContent.severityExamples[$0] ?? ""] }
            }
        }
        return parts.joined(separator: " ").lowercased()
    }
}

/// The help text. Numbers that describe behaviour come from the code, so the
/// help can't drift from what the app actually does.
enum HelpContent {

    static let repositoryURL = URL(string: "https://github.com/MacBachi/CleanPDF")!
    static let issuesURL = URL(string: "https://github.com/MacBachi/CleanPDF/issues")!

    /// What typically lands in each severity (mirrors RiskAnalyzer).
    static let severityExamples: [RiskFinding.Severity: String] = [
        .critical: "JavaScript, automatische Aktionen beim Öffnen, Programmstart, automatischer Aufruf einer Internetadresse",
        .high: "Eingebettete Dateien, Verweise auf andere Dokumente, XFA-Formulare, Multimedia, Formularversand",
        .medium: "Klickbare Links ins Internet, Formulare, nicht lesbare Dateien, abgebrochene Analysen",
        .info: "Digitale Signaturen, interne Verweise wie Inhaltsverzeichnisse, JBIG2-Bilder, Verschlüsselung",
    ]

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Entwicklungsversion"
    }

    private static var timeoutSeconds: Int { Int(IsolatedPDF.defaultPageTimeout) }
    private static var memoryGB: Int { IsolatedPDF.defaultMemoryLimitMB / 1024 }
    private static var megapixels: Int { Int(RenderBudget.maxPixels / 1_000_000) }
    private static let binary = "/Applications/CleanPDF.app/Contents/MacOS/CleanPDF"

    static func topic(_ id: HelpTopicID) -> HelpTopic {
        topics.first { $0.id == id }!
    }

    /// Topics whose text contains every word of `query` (case-insensitive).
    static func search(_ query: String) -> [HelpTopic] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return topics }
        return topics.filter { topic in
            let text = topic.searchableText
            return words.allSatisfy { text.contains($0) }
        }
    }

    static var topics: [HelpTopic] {
        [overview, howItWorks, usage, riskScore, faq, security, commandLine, about]
    }

    // MARK: Überblick

    static var overview: HelpTopic {
        HelpTopic(id: .overview, title: "Überblick", symbol: "shield.lefthalf.filled", blocks: [
            .lead("CleanPDF macht aus PDF-Dateien, denen du nicht vertraust, **garantiert harmlose PDFs** – Seiten, die genauso aussehen wie vorher, aber nichts mehr können."),
            .paragraph("PDFs sind mehr als bedrucktes Papier. Sie können Programmcode enthalten, beim Öffnen unbemerkt Webseiten aufrufen, Dateien mitbringen oder melden, wann und wo du sie geöffnet hast. CleanPDF entfernt all das zuverlässig, bevor du die Datei öffnest oder weitergibst."),
            .heading("Wofür ist das gut?"),
            .bullets([
                "Anhänge von Unbekannten: Rechnungen, Bewerbungen, Mahnungen, „Dokumente zur Ansicht“",
                "PDFs aus Downloads, Foren oder Messengern",
                "Dokumente, bei denen du nicht verraten willst, dass, wann und von wo du sie gelesen hast",
                "Dateien, die du sicher an andere weitergeben möchtest",
            ]),
            .heading("Was wird entfernt?"),
            .bullets([
                "**Programmcode** (JavaScript) und **automatische Aktionen** beim Öffnen",
                "**Links und Tracking** – auch unsichtbare „Canaries“, die beim Öffnen melden, dass eine Datei gelesen wurde",
                "**Eingebettete Dateien** und Anhänge",
                "**Formulare**, Multimedia-Inhalte und Verweise auf andere Dateien",
                "**Digitale Signaturen und Zertifikate**",
                "**Metadaten** des Originals wie Autor, Programm und Zeitstempel",
            ]),
            .heading("Was bleibt?"),
            .paragraph("Das Aussehen jeder Seite – Text, Bilder, Farben, Layout. Wenn du „Durchsuchbar (OCR)“ eingeschaltet lässt, kannst du den Text außerdem weiterhin suchen und kopieren."),
            .heading("Was bekommst du?"),
            .paragraph("Eine **neue Datei** neben dem Original, mit dem Zusatz „(safe)“ im Namen, z. B. `Rechnung (safe).pdf`. Das Original bleibt unverändert."),
            .note(title: "Alles bleibt auf deinem Mac",
                  text: "CleanPDF arbeitet vollständig offline. Keine Datei und keine Information verlässt deinen Computer."),
        ])
    }

    // MARK: So funktioniert's

    static var howItWorks: HelpTopic {
        HelpTopic(id: .howItWorks, title: "So funktioniert's", symbol: "gearshape.2", blocks: [
            .lead("Kurz gesagt: CleanPDF „fotografiert“ jede Seite in einem abgeschotteten Bereich und baut aus den Fotos ein komplett neues PDF."),
            .pipelineDiagram,
            .steps([
                (title: "Abschotten",
                 text: "Die Datei wird nur in einem eigenen Hilfsprozess geöffnet. Der sperrt sich vorher selbst ein: kein Internet, kein Zugriff auf deine Dateien, keine Programmstarts. Selbst ein PDF, das gezielt eine Schwachstelle im PDF-Programm ausnutzt, kommt dort nicht heraus."),
                (title: "Seiten als Bild erfassen",
                 text: "Der Hilfsprozess zeichnet jede Seite als Bild – wie ein Foto des Bildschirms. Zurück an CleanPDF gibt er ausschließlich die Seitengröße und die Bildpunkte. CleanPDF prüft beides streng, bevor es damit arbeitet."),
                (title: "Neu aufbauen",
                 text: "Aus den Bildern baut CleanPDF ein **komplett neues PDF**. Vom Original wird nichts übernommen – deshalb kann darin auch nichts Aktives mehr stecken."),
                (title: "Durchsuchbar machen",
                 text: "Optional erkennt die Texterkennung von macOS den Text auf den Bildern und legt ihn unsichtbar darüber. So kannst du suchen und kopieren. Die Sprache wird je Seite automatisch erkannt."),
                (title: "Gegenprobe",
                 text: "Zum Schluss prüft CleanPDF die neue Datei noch einmal. Nur wenn darin nichts Aktives gefunden wird, erscheint „Ausgabe geprüft“."),
            ]),
            .note(title: "Warum nicht einfach die gefährlichen Teile löschen?",
                  text: "PDFs können aktive Inhalte an unzähligen Stellen verstecken, und Filter übersehen leicht etwas. Ein Neuaufbau aus reinen Bildpunkten lässt dafür schlicht keinen Platz. Nach demselben Prinzip arbeitet das bekannte Werkzeug Dangerzone."),
            .heading("Zusätzliche Schutzmechanismen"),
            .bullets([
                "Braucht eine Seite länger als **\(timeoutSeconds) Sekunden**, wird die Verarbeitung abgebrochen.",
                "Belegt der Hilfsprozess mehr als **\(memoryGB) GB Arbeitsspeicher**, wird er beendet.",
                "Übergroße Seiten (z. B. Plakate) werden mit höchstens **\(megapixels) Megapixeln** erfasst – das genügt für DIN A2 bei 300 dpi.",
                "Kann die Abschottung nicht eingerichtet werden, **verweigert CleanPDF die Arbeit**, statt ungeschützt weiterzumachen.",
            ]),
        ])
    }

    // MARK: Benutzung

    static var usage: HelpTopic {
        HelpTopic(id: .usage, title: "Benutzung", symbol: "hand.point.up.left", blocks: [
            .lead("PDF hineinziehen – den Rest erledigt CleanPDF."),
            .steps([
                (title: "Datei hinzufügen",
                 text: "Zieh eine oder mehrere PDF-Dateien ins Fenster oder auf das CleanPDF-Symbol im Dock. Alternativ: „Datei auswählen …“."),
                (title: "Analyse ansehen",
                 text: "Sofort erscheint der **Risiko-Score** des Originals. Ein Klick darauf zeigt, was in der Datei steckt."),
                (title: "Bereinigung abwarten",
                 text: "Die Bereinigung startet automatisch; der Fortschritt steht unter dem Dateinamen. Mehrere Dateien werden nacheinander bearbeitet."),
                (title: "Ergebnis öffnen",
                 text: "Ist alles erledigt, erscheinen ein grünes Siegel und „Ausgabe geprüft“. „Im Finder zeigen“ führt dich zur neuen Datei."),
            ]),
            .heading("Einstellungen"),
            .bullets([
                "**Auflösung** – 200 dpi ist ein guter Standard. 300 dpi für Kleingedrucktes (größere Dateien), 150 dpi für kleinere Dateien.",
                "**Durchsuchbar (OCR)** – legt eine unsichtbare Textebene an, damit du suchen und kopieren kannst. Ausschalten macht die Bereinigung schneller.",
            ]),
            .heading("Symbole in der Liste"),
            .bullets([
                "Uhr – wartet auf die Bearbeitung",
                "Drehendes Rad – wird gerade bereinigt",
                "Grünes Siegel – fertig",
                "Oranges Dreieck – Fehler; die Meldung darunter erklärt den Grund",
            ]),
            .paragraph("„Liste leeren“ entfernt nur die Einträge aus der Liste – deine Dateien bleiben erhalten. Gibt es schon eine Datei mit „(safe)“ im Namen, legt CleanPDF eine neue mit „(safe 2)“ usw. an."),
            .note(title: "Tastenkürzel", text: "⌘? öffnet jederzeit diese Hilfe."),
        ])
    }

    // MARK: Risiko-Score

    static var riskScore: HelpTopic {
        HelpTopic(id: .riskScore, title: "Risiko-Score", symbol: "gauge.with.dots.needle.33percent", blocks: [
            .lead("Der Risiko-Score zeigt, was im **Original** steckt – von 0 (unauffällig) bis 100 (kritisch)."),
            .paragraph("Die Analyse läuft beim Hinzufügen sofort und ebenfalls im abgeschotteten Hilfsprozess. Sie ist eine Information für dich; bereinigt wird **immer**, egal wie hoch der Score ist."),
            .heading("Stufen"),
            .scoreLevels,
            .heading("Wie der Score entsteht"),
            .paragraph("Jeder Fund zählt Punkte nach seinem Schweregrad; die Summe ergibt den Score (höchstens 100)."),
            .severityTable,
            .heading("Details ansehen"),
            .paragraph("Ein Klick auf den Score klappt die Funde auf – samt gefundener Internetadressen und, falls vorhanden, dem enthaltenen Programmcode. Du kannst alles markieren und kopieren."),
            .warning(title: "Score 0 heißt nicht „garantiert harmlos“",
                     text: "Er bedeutet: keine bekannten aktiven Elemente gefunden. Die eigentliche Sicherheit kommt von der Bereinigung, die immer alles neu aufbaut."),
            .heading("„Ausgabe geprüft“"),
            .paragraph("Nach der Bereinigung analysiert CleanPDF die neue Datei erneut. Das grüne „Ausgabe geprüft“ erscheint nur, wenn dabei nichts gefunden wurde. Zeigt sich stattdessen rot „Prüfung: …“, melde das bitte – das sollte nie passieren."),
            .heading("„Analyse abgebrochen“"),
            .paragraph("Ist der Hilfsprozess bei der Analyse abgestürzt oder hat er zu lange gebraucht, wird das selbst als Fund gemeldet: Die Datei ist dann beschädigt oder womöglich gezielt manipuliert."),
        ])
    }

    // MARK: Häufige Fragen

    static var faq: HelpTopic {
        HelpTopic(id: .faq, title: "Häufige Fragen", symbol: "questionmark.bubble", blocks: [
            .question("macOS sagt, CleanPDF kann nicht geöffnet werden.",
                      answer: "CleanPDF ist kostenlos und nicht bei Apple notarisiert. Öffne beim ersten Mal **Systemeinstellungen → Datenschutz & Sicherheit** und klicke dort bei CleanPDF auf **„Dennoch öffnen“**. Unter macOS 14 genügt auch Rechtsklick auf die App → „Öffnen“."),
            .question("Mein PDF ist passwortgeschützt.",
                      answer: "Öffne es in Vorschau, gib das Passwort ein und wähle **Ablage → Als PDF exportieren** (ohne Verschlüsselung). Die exportierte Datei kann CleanPDF bereinigen."),
            .question("Warum ist die neue Datei größer?",
                      answer: "Jede Seite ist jetzt ein Bild statt Text und Vektorgrafik. Mit 150 dpi werden die Dateien kleiner, mit 300 dpi schärfer."),
            .question("Kann ich den Text noch suchen und kopieren?",
                      answer: "Ja, wenn „Durchsuchbar (OCR)“ eingeschaltet ist. Die Erkennung klappt sehr gut bei lateinischer und kyrillischer Schrift sowie bei Chinesisch, Japanisch, Koreanisch und Thai. Arabisch und Hebräisch erkennt macOS bisher nur eingeschränkt."),
            .question("Die Links im PDF funktionieren nicht mehr.",
                      answer: "Das ist Absicht – Links sind einer der Wege, über die PDFs nach außen telefonieren. Gedruckte Adressen bleiben lesbar; kopiere sie bewusst, wenn du ihnen traust."),
            .question("Es erscheint „mit reduzierter Auflösung gerendert“.",
                      answer: "Die Seite ist größer als \(megapixels) Megapixel bei der gewählten Auflösung, etwa ein großes Plakat. CleanPDF erfasst sie dann etwas gröber, damit eine Datei nicht deinen Arbeitsspeicher füllen kann. Die Seitengröße bleibt gleich."),
            .question("„Zeitüberschreitung“ oder „Speichergrenze überschritten“.",
                      answer: "Eine Seite war ungewöhnlich aufwendig. Das kann ein extrem komplexes, aber harmloses Dokument sein – oder eine Datei, die absichtlich Rechner lahmlegen soll. CleanPDF bricht zum Schutz ab. Für legitime Ausnahmen lassen sich die Grenzen über die Kommandozeile anheben (siehe „Kommandozeile“)."),
            .question("„Sandbox nicht verfügbar“.",
                      answer: "CleanPDF konnte die Abschottung nicht einrichten und verarbeitet die Datei deshalb absichtlich nicht. Das passiert, wenn CleanPDF selbst in einer fremden Sandbox gestartet wurde. Der Selbsttest unter „Sicherheit & Grenzen“ zeigt, ob die Abschottung auf deinem Mac funktioniert. Bleibt der Fehler, melde ihn bitte."),
            .question("Was passiert mit Formularen und Unterschriften?",
                      answer: "Ausgefüllte Inhalte bleiben als Bild sichtbar, das Formular lässt sich aber nicht mehr bearbeiten. Digitale Signaturen fallen weg – ihre Gültigkeit kannst du nur im Original prüfen."),
            .question("Wird mein Original verändert?",
                      answer: "Nein. CleanPDF liest das Original nur und legt immer eine neue Datei an."),
        ])
    }

    // MARK: Sicherheit & Grenzen

    static var security: HelpTopic {
        HelpTopic(id: .security, title: "Sicherheit & Grenzen", symbol: "lock.shield", blocks: [
            .lead("Was CleanPDF zusichert – und was nicht."),
            .heading("Zugesichert"),
            .bullets([
                "Die neue Datei enthält **keine aktiven Inhalte**: keinen Code, keine Links, keine Anhänge, keine Formulare, keine Signaturen, keine Metadaten des Originals.",
                "Das Original wird **nur im abgeschotteten Hilfsprozess** geöffnet – ohne Internet, ohne Zugriff auf deine Dateien, ohne Programmstarts.",
                "Ohne funktionierende Abschottung findet **keine Verarbeitung** statt.",
                "Alles läuft **offline**; es werden keine Daten gesendet.",
            ]),
            .heading("Nicht abgedeckt"),
            .bullets([
                "**Der Inhalt selbst.** CleanPDF entfernt Technik, keine Lügen: Eine gefälschte Rechnung bleibt eine gefälschte Rechnung, und ein gedruckter QR-Code oder eine Webadresse kann weiterhin auf eine betrügerische Seite führen.",
                "**Angriffe auf den macOS-Kern.** Die Abschottung ist eine Prozess-Sandbox, keine virtuelle Maschine. Ein Angriff, der zusätzlich macOS selbst überwindet, liegt außerhalb dessen, wovor CleanPDF schützt. Wer gezielt angegriffen wird, sollte zusätzlich eine virtuelle Maschine bzw. Dangerzone verwenden.",
            ]),
            .heading("Abschottung selbst prüfen"),
            .paragraph("Im Terminal kannst du testen, ob die Abschottung auf deinem Mac greift. CleanPDF versucht dann, eine Datei zu lesen, eine Datei zu schreiben, ins Internet zu gehen und ein Programm zu starten – alles muss blockiert sein:"),
            .code("\(binary) \\\n    --sandbox-selftest /etc/hosts /tmp"),
            .paragraph("Am Ende sollte `result: all blocked` stehen. Datei und Ordner müssen existieren; geprüft wird, ob CleanPDF sie trotzdem nicht erreicht."),
        ])
    }

    // MARK: Kommandozeile

    static var commandLine: HelpTopic {
        HelpTopic(id: .commandLine, title: "Kommandozeile", symbol: "terminal", blocks: [
            .lead("CleanPDF lässt sich auch aus dem Terminal und in Skripten nutzen."),
            .paragraph("Das Programm steckt in der App. Ein Alias erspart das Abtippen des Pfads (für dauerhaft in `~/.zshrc` eintragen):"),
            .code("alias cleanpdf=\(binary)"),
            .code("cleanpdf [--scan] [--dpi N] [--no-ocr] [--output <Ordner>] datei.pdf …"),
            .bullets([
                "`--scan` – nur analysieren, nichts bereinigen. Rückgabewert 0 = unauffällig, 1 = Funde.",
                "`--dpi N` – Auflösung zwischen 72 und 600 (Standard 200).",
                "`--no-ocr` – keine Textebene anlegen.",
                "`--output <Ordner>` – Ergebnisse in einen Ordner schreiben statt neben das Original.",
                "`--sandbox-selftest <Datei> <Ordner>` – Abschottung prüfen (siehe „Sicherheit & Grenzen“).",
            ]),
            .heading("Grenzen anpassen"),
            .paragraph("Für ungewöhnlich aufwendige, aber vertrauenswürdige Dateien lassen sich die Schutzgrenzen anheben:"),
            .code("CLEANPDF_PAGE_TIMEOUT=600 CLEANPDF_WORKER_MEMORY_MB=8192 cleanpdf plan.pdf"),
            .bullets([
                "`CLEANPDF_PAGE_TIMEOUT` – Sekunden pro Seite (Standard \(timeoutSeconds))",
                "`CLEANPDF_WORKER_MEMORY_MB` – Speichergrenze des Hilfsprozesses in MB (Standard \(IsolatedPDF.defaultMemoryLimitMB))",
            ]),
        ])
    }

    // MARK: Über

    static var about: HelpTopic {
        HelpTopic(id: .about, title: "Über CleanPDF", symbol: "info.circle", blocks: [
            .lead("CleanPDF \(version)"),
            .paragraph("CleanPDF ist freie Software unter der **GNU General Public License v3**. Du darfst es kostenlos nutzen, weitergeben und verändern."),
            .paragraph("Quellcode, Versionen und Änderungen: [github.com/MacBachi/CleanPDF](https://github.com/MacBachi/CleanPDF)"),
            .paragraph("Fehler gefunden oder eine Idee? [Problem melden](https://github.com/MacBachi/CleanPDF/issues) – bei Sicherheitslücken bitte über „Report a vulnerability“ auf GitHub."),
        ])
    }
}
