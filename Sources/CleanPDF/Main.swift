// CleanPDF — turn untrusted PDFs into guaranteed-passive, safe PDFs.
// Copyright (C) 2026 CleanPDF contributors
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. This program is distributed WITHOUT ANY WARRANTY; see
// the GNU General Public License <https://www.gnu.org/licenses/> for details.

import Foundation

/// Entry point. With file arguments the tool runs headless (CLI mode);
/// without arguments the SwiftUI app starts.
///
/// CLI usage:
///   CleanPDF [--dpi N] [--no-ocr] [--output <dir>] file.pdf [more.pdf ...]
@main
struct Entry {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())
        // macOS may pass process serial numbers / AppKit flags when launched
        // from Finder; those must not trigger CLI mode.
        args.removeAll { $0.hasPrefix("-psn_") || $0.hasPrefix("-NS") || $0.hasPrefix("-Apple") }

        if args.isEmpty {
            CleanPDFApp.main()
        } else {
            exit(runCLI(args))
        }
    }

    private static func runCLI(_ args: [String]) -> Int32 {
        var options = SanitizeOptions()
        var outputDir: URL?
        var inputs: [URL] = []
        var scanOnly = false

        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--dpi":
                index += 1
                guard index < args.count, let value = Double(args[index]), value >= 72, value <= 600 else {
                    FileHandle.standardError.write(Data("Fehler: --dpi erwartet einen Wert zwischen 72 und 600.\n".utf8))
                    return 2
                }
                options.dpi = CGFloat(value)
            case "--no-ocr":
                options.ocr = false
            case "--scan":
                scanOnly = true
            case "--output":
                index += 1
                guard index < args.count else {
                    FileHandle.standardError.write(Data("Fehler: --output erwartet ein Verzeichnis.\n".utf8))
                    return 2
                }
                outputDir = URL(fileURLWithPath: args[index], isDirectory: true)
            case "--help", "-h":
                print("Usage: CleanPDF [--scan] [--dpi N] [--no-ocr] [--output <dir>] file.pdf [more.pdf ...]")
                print("  --scan    nur Risiko-Analyse ausgeben, nichts bereinigen")
                return 0
            default:
                inputs.append(URL(fileURLWithPath: arg))
            }
            index += 1
        }

        guard !inputs.isEmpty else {
            FileHandle.standardError.write(Data("Fehler: keine Eingabedateien angegeben.\n".utf8))
            return 2
        }

        var failures = 0
        var maxScore = 0
        for input in inputs {
            let report = RiskAnalyzer.analyze(url: input)
            maxScore = max(maxScore, report.score)
            printReport(report, file: input.lastPathComponent)

            if scanOnly { continue }

            let output: URL
            if let dir = outputDir {
                output = JobQueue.outputURL(for: dir.appendingPathComponent(input.lastPathComponent))
            } else {
                output = JobQueue.outputURL(for: input)
            }
            do {
                try Sanitizer.sanitize(input: input, output: output, options: options) { page, count in
                    FileHandle.standardError.write(Data("\(input.lastPathComponent): Seite \(page)/\(count)\n".utf8))
                }
                let verification = RiskAnalyzer.analyze(url: output)
                if verification.score == 0 {
                    print("OK  \(output.path)  [Ausgabe geprüft: keine aktiven Elemente]")
                } else {
                    print("WARNUNG  \(output.path)  [Ausgabe-Prüfung fand noch Score \(verification.score)!]")
                    printReport(verification, file: output.lastPathComponent)
                    failures += 1
                }
            } catch {
                failures += 1
                FileHandle.standardError.write(Data("FEHLER  \(input.path): \(error.localizedDescription)\n".utf8))
            }
        }
        // --scan: exit code signals risk (0 = clean, 1 = findings) for scripting.
        if scanOnly { return maxScore > 0 ? 1 : 0 }
        return failures == 0 ? 0 : 1
    }

    private static func printReport(_ report: RiskReport, file: String) {
        print("RISIKO \(report.score)/100 (\(report.levelLabel))  \(file)")
        for finding in report.sortedFindings {
            print("  [\(finding.severity.label)] \(finding.title)")
            for detail in finding.details {
                print("      \(detail)")
            }
        }
    }
}