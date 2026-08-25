// CleanPDF — turn untrusted PDFs into guaranteed-passive, safe PDFs.
// Copyright (C) 2026 CleanPDF contributors
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. This program is distributed WITHOUT ANY WARRANTY; see
// the GNU General Public License <https://www.gnu.org/licenses/> for details.

import Foundation
import CoreGraphics

// MARK: - Report model

struct RiskFinding: Identifiable, Sendable {
    enum Severity: Int, Comparable, Sendable {
        case info = 0      // noteworthy, not dangerous (e.g. signature)
        case medium = 1    // external references, forms
        case high = 2      // embedded files, external file actions, multimedia
        case critical = 3  // JavaScript, auto-run actions, Launch

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

        var points: Int {
            switch self {
            case .info: return 0
            case .medium: return 10
            case .high: return 25
            case .critical: return 40
            }
        }

        var label: String {
            switch self {
            case .info: return "Hinweis"
            case .medium: return "Mittel"
            case .high: return "Hoch"
            case .critical: return "Kritisch"
            }
        }
    }

    let id = UUID()
    var severity: Severity
    var title: String
    var details: [String] = []
}

struct RiskReport: Sendable {
    var findings: [RiskFinding]

    /// 0–100, capped sum of finding points, sorted by severity.
    var score: Int {
        min(100, findings.reduce(0) { $0 + $1.severity.points })
    }

    var levelLabel: String {
        switch score {
        case 0: return "Unauffällig"
        case 1..<20: return "Niedrig"
        case 20..<40: return "Mittel"
        case 40..<70: return "Hoch"
        default: return "Kritisch"
        }
    }

    var sortedFindings: [RiskFinding] {
        findings.sorted { $0.severity > $1.severity }
    }
}

// MARK: - Analyzer

/// Scans a PDF for potentially dangerous elements WITHOUT rendering it.
///
/// Two layers:
/// 1. Structural walk of the parsed object tree (CGPDFDocument) — targeted
///    probes of the places active content lives: catalog OpenAction/AA/Names/
///    AcroForm, per-page AA and annotations with their actions. This also
///    sees content hidden inside compressed object streams, because CGPDF
///    parses those transparently.
/// 2. Raw byte scan for marker names as a safety net for malformed or
///    deliberately obfuscated files. Raw-only hits are reported separately,
///    since they can be inactive leftovers.
enum RiskAnalyzer {

    static func analyze(url: URL) -> RiskReport {
        var findings: [RiskFinding] = []
        var structuralMarkers = Set<String>()

        if let doc = CGPDFDocument(url as CFURL) {
            if doc.isEncrypted {
                findings.append(RiskFinding(
                    severity: .info,
                    title: "PDF ist verschlüsselt/passwortgeschützt"
                ))
            }
            structuralScan(doc: doc, findings: &findings, markers: &structuralMarkers)
        } else {
            findings.append(RiskFinding(
                severity: .medium,
                title: "Datei konnte nicht als PDF geparst werden",
                details: ["Struktur-Analyse nicht möglich; nur Rohdaten-Scan."]
            ))
        }

        rawScan(url: url, structuralMarkers: structuralMarkers, findings: &findings)
        return RiskReport(findings: findings)
    }

    // MARK: Structural scan

    private static func structuralScan(
        doc: CGPDFDocument,
        findings: inout [RiskFinding],
        markers: inout Set<String>
    ) {
        guard let catalog = doc.catalog else { return }

        // --- Document-level auto actions -------------------------------
        var openAction: CGPDFObjectRef?
        if CGPDFDictionaryGetObject(catalog, "OpenAction", &openAction), let openAction {
            markers.insert("/OpenAction")
            var dict: CGPDFDictionaryRef?
            if CGPDFObjectGetValue(openAction, .dictionary, &dict), let dict {
                classifyAction(dict, context: "Beim Öffnen des Dokuments", auto: true, findings: &findings, markers: &markers)
            }
            // An array OpenAction is just a go-to-page destination — benign.
        }

        var docAA: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(catalog, "AA", &docAA), let docAA {
            markers.insert("/AA")
            classifyAdditionalActions(docAA, context: "Dokument-Ereignis", findings: &findings, markers: &markers)
        }

        // --- Names tree: document-level JavaScript & attachments -------
        var names: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(catalog, "Names", &names), let names {
            var jsTree: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(names, "JavaScript", &jsTree), let jsTree {
                markers.insert("/JavaScript")
                var scriptNames: [String] = []
                collectNamesTreeKeys(jsTree, into: &scriptNames)
                findings.append(RiskFinding(
                    severity: .critical,
                    title: "Dokumentweite JavaScript-Skripte",
                    details: scriptNames.isEmpty ? ["Skript-Verzeichnis vorhanden"] : scriptNames.prefix(10).map { "Skript: \($0)" }
                ))
            }
            var efTree: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(names, "EmbeddedFiles", &efTree), let efTree {
                markers.insert("/EmbeddedFiles")
                markers.insert("/EmbeddedFile")
                var fileNames: [String] = []
                collectNamesTreeKeys(efTree, into: &fileNames)
                findings.append(RiskFinding(
                    severity: .high,
                    title: "Eingebettete Dateien (Anhänge)",
                    details: fileNames.isEmpty ? ["Anhangs-Verzeichnis vorhanden"] : fileNames.prefix(25).map { "Datei: \($0)" }
                ))
            }
        }

        // --- Forms ------------------------------------------------------
        var acroForm: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(catalog, "AcroForm", &acroForm), let acroForm {
            markers.insert("/AcroForm")
            var xfa: CGPDFObjectRef?
            if CGPDFDictionaryGetObject(acroForm, "XFA", &xfa) {
                markers.insert("/XFA")
                findings.append(RiskFinding(
                    severity: .high,
                    title: "XFA-Formular (XML Forms Architecture)",
                    details: ["XFA kann eigene Skript-Logik enthalten."]
                ))
            }
            var fields: CGPDFArrayRef?
            var fieldCount = 0
            if CGPDFDictionaryGetArray(acroForm, "Fields", &fields), let fields {
                fieldCount = CGPDFArrayGetCount(fields)
            }
            if fieldCount > 0 || xfa == nil {
                findings.append(RiskFinding(
                    severity: .medium,
                    title: "Interaktives Formular (AcroForm)",
                    details: fieldCount > 0 ? ["\(fieldCount) Formularfeld(er) auf oberster Ebene"] : []
                ))
            }
            var sigFlags: CGPDFInteger = 0
            if CGPDFDictionaryGetInteger(acroForm, "SigFlags", &sigFlags), sigFlags != 0 {
                markers.insert("/Sig")
                findings.append(RiskFinding(
                    severity: .info,
                    title: "Digitale Signatur vorhanden",
                    details: ["Signaturen/Zertifikate werden bei der Bereinigung entfernt."]
                ))
            }
        }

        // Base URI at document level (prepended to relative links).
        var uriDict: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(catalog, "URI", &uriDict), let uriDict {
            markers.insert("/URI")
            var base: CGPDFStringRef?
            var detail: [String] = []
            if CGPDFDictionaryGetString(uriDict, "Base", &base), let s = pdfString(base) {
                detail = ["Basis-URL: \(s)"]
            }
            findings.append(RiskFinding(severity: .medium, title: "Dokumentweite Basis-URL", details: detail))
        }

        // --- Pages: annotations and page actions -----------------------
        var linkURIs: [String] = []
        var internalLinkCount = 0
        var attachmentCount = 0
        var multimediaTypes = Set<String>()
        var widgetCount = 0

        for pageNumber in 1...max(1, doc.numberOfPages) {
            guard let page = doc.page(at: pageNumber), let pageDict = page.dictionary else { continue }

            var pageAA: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(pageDict, "AA", &pageAA), let pageAA {
                markers.insert("/AA")
                classifyAdditionalActions(pageAA, context: "Seite \(pageNumber)", findings: &findings, markers: &markers)
            }

            var annots: CGPDFArrayRef?
            guard CGPDFDictionaryGetArray(pageDict, "Annots", &annots), let annots else { continue }

            for i in 0..<CGPDFArrayGetCount(annots) {
                var annot: CGPDFDictionaryRef?
                guard CGPDFArrayGetDictionary(annots, i, &annot), let annot else { continue }

                var subtypePtr: UnsafePointer<Int8>?
                let subtype = CGPDFDictionaryGetName(annot, "Subtype", &subtypePtr)
                    ? String(cString: subtypePtr!) : "?"

                switch subtype {
                case "Link":
                    // External only if the link carries a URI action; links
                    // with /Dest or a GoTo action just navigate inside the
                    // document (tables of contents etc.) — those are benign.
                    var linkAction: CGPDFDictionaryRef?
                    var actionTypePtr: UnsafePointer<Int8>?
                    let isExternal = CGPDFDictionaryGetDictionary(annot, "A", &linkAction)
                        && linkAction != nil
                        && CGPDFDictionaryGetName(linkAction!, "S", &actionTypePtr)
                        && ["URI", "GoToR", "GoToE", "Launch", "SubmitForm", "JavaScript"]
                            .contains(String(cString: actionTypePtr!))
                    if !isExternal {
                        internalLinkCount += 1
                    }
                case "FileAttachment":
                    markers.insert("/EmbeddedFile")
                    attachmentCount += 1
                case "RichMedia", "Movie", "Sound", "Screen", "3D":
                    markers.insert("/\(subtype)")
                    multimediaTypes.insert(subtype)
                case "Widget":
                    widgetCount += 1
                default:
                    break
                }

                var action: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(annot, "A", &action), let action {
                    classifyAction(action, context: "Seite \(pageNumber)", auto: false,
                                   findings: &findings, markers: &markers, collectURIsInto: &linkURIs)
                }
                var annotAA: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(annot, "AA", &annotAA), let annotAA {
                    markers.insert("/AA")
                    classifyAdditionalActions(annotAA, context: "Element auf Seite \(pageNumber)", findings: &findings, markers: &markers)
                }
            }
        }

        if !linkURIs.isEmpty {
            markers.insert("/Link")
            let unique = Array(Set(linkURIs)).sorted()
            let cap = 100
            findings.append(RiskFinding(
                severity: .medium,
                title: "Externe Links (\(linkURIs.count) URL-Aktion(en), \(unique.count) eindeutige URL(s))",
                details: unique.prefix(cap).map { "URL: \($0)" }
                    + (unique.count > cap ? ["… und \(unique.count - cap) weitere"] : [])
            ))
        }
        if internalLinkCount > 0 {
            findings.append(RiskFinding(
                severity: .info,
                title: "Interne Verweise (\(internalLinkCount)) – Navigation innerhalb des Dokuments",
                details: ["Z. B. Inhaltsverzeichnis oder Seiten-Sprungmarken; kein Zugriff nach außen.",
                          "Werden bei der Bereinigung trotzdem entfernt."]
            ))
        }
        if attachmentCount > 0 {
            findings.append(RiskFinding(
                severity: .high,
                title: "Dateianhang-Annotationen",
                details: ["\(attachmentCount) angeheftete Datei(en) auf Seiten"]
            ))
        }
        if !multimediaTypes.isEmpty {
            findings.append(RiskFinding(
                severity: .high,
                title: "Multimedia-Inhalte",
                details: multimediaTypes.sorted().map { "Typ: \($0)" }
            ))
        }
        if widgetCount > 0 && !findings.contains(where: { $0.title.contains("AcroForm") }) {
            findings.append(RiskFinding(
                severity: .medium,
                title: "Formularfelder auf Seiten",
                details: ["\(widgetCount) Feld(er)"]
            ))
        }
    }

    /// Classifies a single action dictionary (and its /Next chain).
    private static func classifyAction(
        _ action: CGPDFDictionaryRef,
        context: String,
        auto: Bool,
        findings: inout [RiskFinding],
        markers: inout Set<String>,
        collectURIsInto uriSink: UnsafeMutablePointer<[String]>? = nil,
        depth: Int = 0
    ) {
        guard depth < 8 else { return }
        var sPtr: UnsafePointer<Int8>?
        guard CGPDFDictionaryGetName(action, "S", &sPtr), let sPtr else { return }
        let type = String(cString: sPtr)
        let autoNote = auto ? " (läuft automatisch!)" : ""

        switch type {
        case "JavaScript":
            markers.insert("/JavaScript")
            markers.insert("/JS")
            var snippet: [String] = []
            var js: CGPDFStringRef?
            if CGPDFDictionaryGetString(action, "JS", &js), let s = pdfString(js) {
                snippet = codeDetails(s)
            } else if let s = pdfStreamText(action, key: "JS") {
                // /JS may also be a stream object instead of a string.
                snippet = codeDetails(s)
            }
            findings.append(RiskFinding(severity: .critical,
                                        title: "JavaScript-Aktion – \(context)\(autoNote)",
                                        details: snippet))
        case "Launch":
            markers.insert("/Launch")
            findings.append(RiskFinding(severity: .critical,
                                        title: "Launch-Aktion (startet externe Datei/Programm) – \(context)\(autoNote)"))
        case "URI":
            markers.insert("/URI")
            var uri: CGPDFStringRef?
            let url = (CGPDFDictionaryGetString(action, "URI", &uri) ? pdfString(uri) : nil) ?? "?"
            if auto {
                findings.append(RiskFinding(severity: .critical,
                                            title: "Automatischer URL-Aufruf – \(context)",
                                            details: ["URL: \(url)"]))
            } else if let sink = uriSink {
                sink.pointee.append(url)
            } else {
                findings.append(RiskFinding(severity: .medium,
                                            title: "URL-Aktion – \(context)",
                                            details: ["URL: \(url)"]))
            }
        case "SubmitForm":
            markers.insert("/SubmitForm")
            var f: CGPDFDictionaryRef?
            var target: [String] = []
            if CGPDFDictionaryGetDictionary(action, "F", &f), let f {
                var fs: CGPDFStringRef?
                if CGPDFDictionaryGetString(f, "F", &fs), let s = pdfString(fs) { target = ["Ziel: \(s)"] }
            } else {
                var fs: CGPDFStringRef?
                if CGPDFDictionaryGetString(action, "F", &fs), let s = pdfString(fs) { target = ["Ziel: \(s)"] }
            }
            findings.append(RiskFinding(severity: auto ? .critical : .high,
                                        title: "Formular-Versand an externe Adresse – \(context)\(autoNote)",
                                        details: target))
        case "ImportData":
            markers.insert("/ImportData")
            findings.append(RiskFinding(severity: .high,
                                        title: "Datenimport aus externer Datei – \(context)\(autoNote)"))
        case "GoToR", "GoToE":
            markers.insert("/\(type)")
            findings.append(RiskFinding(severity: .high,
                                        title: "Verweis auf externes/eingebettetes Dokument (\(type)) – \(context)\(autoNote)"))
        case "Rendition", "Movie", "Sound":
            markers.insert("/\(type)")
            findings.append(RiskFinding(severity: .high,
                                        title: "Multimedia-Aktion (\(type)) – \(context)\(autoNote)"))
        default:
            break // GoTo, Named etc. — internal navigation, benign
        }

        var next: CGPDFObjectRef?
        if CGPDFDictionaryGetObject(action, "Next", &next), let next {
            var nextDict: CGPDFDictionaryRef?
            if CGPDFObjectGetValue(next, .dictionary, &nextDict), let nextDict {
                classifyAction(nextDict, context: context, auto: auto,
                               findings: &findings, markers: &markers,
                               collectURIsInto: uriSink, depth: depth + 1)
            }
        }
    }

    /// /AA dictionaries map event names to actions; every entry is auto-run.
    /// Probes all event keys defined by the PDF spec (doc, page, annot, field).
    private static func classifyAdditionalActions(
        _ aa: CGPDFDictionaryRef,
        context: String,
        findings: inout [RiskFinding],
        markers: inout Set<String>
    ) {
        let eventKeys = [
            "O", "C",                                  // page open/close
            "WC", "WS", "DS", "WP", "DP",              // document will-close/save/print
            "E", "X", "D", "U", "Fo", "Bl", "PO", "PC", "PV", "PI", // annotation events
            "K", "F", "V",                             // form field events
        ]
        for key in eventKeys {
            var dict: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(aa, key, &dict), let dict {
                classifyAction(dict, context: context, auto: true, findings: &findings, markers: &markers)
            }
        }
    }

    /// Collects the string keys of a PDF name tree (with /Kids recursion).
    private static func collectNamesTreeKeys(
        _ tree: CGPDFDictionaryRef, into result: inout [String], depth: Int = 0
    ) {
        guard depth < 16, result.count < 50 else { return }
        var namesArray: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(tree, "Names", &namesArray), let namesArray {
            let count = CGPDFArrayGetCount(namesArray)
            var i = 0
            while i + 1 < count {
                var str: CGPDFStringRef?
                if CGPDFArrayGetString(namesArray, i, &str), let s = pdfString(str) {
                    result.append(s)
                }
                i += 2
            }
        }
        var kids: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(tree, "Kids", &kids), let kids {
            for i in 0..<CGPDFArrayGetCount(kids) {
                var kid: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(kids, i, &kid), let kid {
                    collectNamesTreeKeys(kid, into: &result, depth: depth + 1)
                }
            }
        }
    }

    private static func pdfString(_ ref: CGPDFStringRef?) -> String? {
        guard let ref, let ptr = CGPDFStringGetBytePtr(ref) else { return nil }
        let data = Data(bytes: ptr, count: CGPDFStringGetLength(ref))
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    /// Reads a stream value (e.g. /JS as stream) and decodes it as text.
    private static func pdfStreamText(_ dict: CGPDFDictionaryRef, key: String) -> String? {
        var stream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(dict, key, &stream), let stream else { return nil }
        var format = CGPDFDataFormat.raw
        guard let cfData = CGPDFStreamCopyData(stream, &format) else { return nil }
        let data = cfData as Data
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    /// Prepares script content for display: full code up to a sane cap,
    /// split into lines, marked when truncated.
    private static func codeDetails(_ code: String, cap: Int = 1500) -> [String] {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = String(trimmed.prefix(cap))
        var lines = clipped
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if trimmed.count > cap {
            lines.append("… (gekürzt, insgesamt \(trimmed.count) Zeichen)")
        }
        return lines
    }

    // MARK: Raw byte scan (safety net)

    /// Scans the raw file bytes for marker names the structural scan did not
    /// account for. Catches malformed files and crude obfuscation; hits can
    /// also be inactive leftovers, so they are reported with that caveat.
    ///
    /// Stream contents (between `stream`/`endstream`) are excluded: they are
    /// binary data (images, compressed content) in which short marker byte
    /// sequences like "/JS" occur by pure chance — a multi-megabyte JPEG all
    /// but guarantees such false positives. PDF name keys live in the object
    /// dictionaries outside streams; active content hidden inside compressed
    /// object streams is covered by the structural scan, which parses them.
    private static func rawScan(
        url: URL,
        structuralMarkers: Set<String>,
        findings: inout [RiskFinding]
    ) {
        guard let raw = try? Data(contentsOf: url, options: .mappedIfSafe) else { return }
        let data = strippedOfStreamContents(raw)

        let rawMarkers: [(String, RiskFinding.Severity, String)] = [
            ("/JavaScript", .high, "JavaScript-Marker"),
            ("/JS", .high, "JavaScript-Marker (Kurzform)"),
            ("/OpenAction", .medium, "Auto-Aktions-Marker"),
            ("/Launch", .high, "Launch-Marker"),
            ("/EmbeddedFile", .medium, "Anhangs-Marker"),
            ("/RichMedia", .medium, "Multimedia-Marker"),
            ("/XFA", .medium, "XFA-Marker"),
            ("/SubmitForm", .medium, "Formular-Versand-Marker"),
            ("/ByteRange", .info, "Signatur-Marker"),
        ]

        var rawOnly: [String] = []
        var maxSeverity = RiskFinding.Severity.info
        for (marker, severity, label) in rawMarkers where !structuralMarkers.contains(marker) {
            if containsPDFName(data, marker) {
                rawOnly.append("\(label) (\(marker))")
                maxSeverity = max(maxSeverity, severity)
            }
        }
        // /Sig via ByteRange counts as signature info even structurally unseen.
        if rawOnly.count == 1 && rawOnly[0].contains("/ByteRange") {
            findings.append(RiskFinding(severity: .info,
                                        title: "Digitale Signatur vorhanden (Rohdaten)",
                                        details: ["Wird bei der Bereinigung entfernt."]))
            return
        }
        if !rawOnly.isEmpty {
            findings.append(RiskFinding(
                severity: maxSeverity,
                title: "Marker in Rohdaten, die die Struktur-Analyse nicht erfasst hat",
                details: rawOnly + ["Möglicherweise verschleiert oder inaktive Reste."]
            ))
        }
    }

    /// Removes the bytes between `stream` and `endstream` keywords, keeping
    /// everything else (headers, dictionaries, xref, trailer).
    private static func strippedOfStreamContents(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        let n = bytes.count
        var out = [UInt8]()
        out.reserveCapacity(min(n, 4_000_000))
        let streamKw = Array("stream".utf8)
        let endKw = Array("endstream".utf8)

        func matches(_ index: Int, _ word: [UInt8]) -> Bool {
            guard index + word.count <= n else { return false }
            for j in 0..<word.count where bytes[index + j] != word[j] { return false }
            return true
        }
        func isLetter(_ b: UInt8) -> Bool {
            (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
        }

        var i = 0
        var inStream = false
        while i < n {
            if !inStream {
                // `stream` keyword: not part of a longer word (e.g. `endstream`),
                // followed by an end-of-line marker per PDF spec.
                if bytes[i] == UInt8(ascii: "s"), matches(i, streamKw),
                   i == 0 || !isLetter(bytes[i - 1]),
                   i + streamKw.count < n,
                   bytes[i + streamKw.count] == 0x0A || bytes[i + streamKw.count] == 0x0D {
                    out.append(contentsOf: streamKw)
                    i += streamKw.count
                    inStream = true
                    continue
                }
                out.append(bytes[i])
                i += 1
            } else {
                if bytes[i] == UInt8(ascii: "e"), matches(i, endKw) {
                    out.append(contentsOf: endKw)
                    i += endKw.count
                    inStream = false
                    continue
                }
                i += 1
            }
        }
        return Data(out)
    }

    /// Marker match with PDF-name word boundary (next byte must not continue the name).
    private static func containsPDFName(_ data: Data, _ name: String) -> Bool {
        let needle = Array(name.utf8)
        let bytes = [UInt8](data)
        guard bytes.count >= needle.count else { return false }
        var i = 0
        let end = bytes.count - needle.count
        while i <= end {
            if bytes[i] == needle[0], Array(bytes[i..<i+needle.count]) == needle {
                let nextIndex = i + needle.count
                if nextIndex >= bytes.count || !isPDFNameChar(bytes[nextIndex]) {
                    return true
                }
            }
            i += 1
        }
        return false
    }

    private static func isPDFNameChar(_ b: UInt8) -> Bool {
        (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39)
            || b == 0x23 /* # escape */ || b == 0x3A /* : */
    }
}