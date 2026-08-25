// CleanPDF — turn untrusted PDFs into guaranteed-passive, safe PDFs.
// Copyright (C) 2026 CleanPDF contributors
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. This program is distributed WITHOUT ANY WARRANTY; see
// the GNU General Public License <https://www.gnu.org/licenses/> for details.

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Job model

@MainActor
final class SanitizeJob: ObservableObject, Identifiable {
    enum Status: Equatable {
        case waiting
        case running(page: Int, of: Int)
        case done(output: URL)
        case failed(message: String)
    }

    let id = UUID()
    let input: URL
    @Published var status: Status = .waiting
    /// Risk analysis of the ORIGINAL file (runs immediately on add).
    @Published var report: RiskReport?
    /// Risk analysis of the sanitized output (verification; expected score 0).
    @Published var outputReport: RiskReport?

    init(input: URL) { self.input = input }

    var fileName: String { input.lastPathComponent }
}

@MainActor
final class JobQueue: ObservableObject {
    static let shared = JobQueue()

    @Published var jobs: [SanitizeJob] = []
    @Published var dpi: Double = 200
    @Published var ocrEnabled: Bool = true

    private var isProcessing = false

    func add(urls: [URL]) {
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        guard !pdfs.isEmpty else { return }
        for url in pdfs {
            let job = SanitizeJob(input: url)
            jobs.append(job)
            let jobID = job.id
            Task.detached(priority: .userInitiated) {
                let report = RiskAnalyzer.analyze(url: url)
                await MainActor.run {
                    JobQueue.shared.jobs.first(where: { $0.id == jobID })?.report = report
                }
            }
        }
        processNext()
    }

    func clearFinished() {
        jobs.removeAll {
            if case .waiting = $0.status { return false }
            if case .running = $0.status { return false }
            return true
        }
    }

    private func processNext() {
        guard !isProcessing else { return }
        guard let job = jobs.first(where: { $0.status == .waiting }) else { return }
        isProcessing = true

        var options = SanitizeOptions()
        options.dpi = CGFloat(dpi)
        options.ocr = ocrEnabled

        let input = job.input
        let output = Self.outputURL(for: input)
        let jobID = job.id

        Task.detached(priority: .userInitiated) {
            do {
                try Sanitizer.sanitize(input: input, output: output, options: options) { page, count in
                    Task { @MainActor in
                        JobQueue.shared.update(jobID: jobID, status: .running(page: page, of: count))
                    }
                }
                let verification = RiskAnalyzer.analyze(url: output)
                await MainActor.run {
                    JobQueue.shared.jobs.first(where: { $0.id == jobID })?.outputReport = verification
                    JobQueue.shared.update(jobID: jobID, status: .done(output: output))
                    JobQueue.shared.finishAndContinue()
                }
            } catch {
                await MainActor.run {
                    JobQueue.shared.update(jobID: jobID, status: .failed(message: error.localizedDescription))
                    JobQueue.shared.finishAndContinue()
                }
            }
        }
    }

    private func update(jobID: UUID, status: SanitizeJob.Status) {
        jobs.first(where: { $0.id == jobID })?.status = status
        objectWillChange.send()
    }

    private func finishAndContinue() {
        isProcessing = false
        processNext()
    }

    /// "Report.pdf" -> "Report (safe).pdf", avoiding collisions.
    nonisolated static func outputURL(for input: URL) -> URL {
        let dir = input.deletingLastPathComponent()
        let base = input.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent("\(base) (safe).pdf")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) (safe \(counter)).pdf")
            counter += 1
        }
        return candidate
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            JobQueue.shared.add(urls: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct CleanPDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("CleanPDF") {
            ContentView()
                .frame(minWidth: 520, minHeight: 420)
        }
        .windowResizability(.contentSize)
    }
}

// MARK: - Views

struct ContentView: View {
    @ObservedObject private var queue = JobQueue.shared
    @State private var isDropTargeted = false
    @State private var showingImporter = false

    var body: some View {
        VStack(spacing: 0) {
            dropZone
                .padding()

            Divider()

            if queue.jobs.isEmpty {
                Spacer()
                Text("Noch keine Dateien.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(queue.jobs) { job in
                    JobRow(job: job)
                }
                .listStyle(.inset)
            }

            Divider()
            footer
                .padding(10)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                queue.add(urls: urls)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 36))
                .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
            Text("PDF hier ablegen")
                .font(.headline)
            Text("Jede Seite wird als Bild neu aufgebaut – ohne Skripte, Links, Anhänge, Formulare oder Signaturen.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Datei auswählen …") { showingImporter = true }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Picker("Auflösung:", selection: $queue.dpi) {
                Text("150 dpi").tag(150.0)
                Text("200 dpi").tag(200.0)
                Text("300 dpi").tag(300.0)
            }
            .pickerStyle(.menu)
            .fixedSize()

            Toggle("Durchsuchbar (OCR)", isOn: $queue.ocrEnabled)
                .toggleStyle(.checkbox)

            Spacer()

            Button("Liste leeren") { queue.clearFinished() }
                .disabled(queue.jobs.isEmpty)
        }
        .font(.callout)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    JobQueue.shared.add(urls: [url])
                }
            }
        }
        return accepted
    }
}

struct JobRow: View {
    @ObservedObject var job: SanitizeJob
    @State private var showDetails = false
    @State private var showOutputDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                statusIcon
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.fileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if let report = job.report {
                    RiskBadge(report: report, expanded: $showDetails)
                }

                if case .done(let output) = job.status {
                    verificationBadge
                    Button("Im Finder zeigen") {
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    }
                    .buttonStyle(.link)
                }
            }

            if showDetails, let report = job.report {
                RiskDetailList(report: report)
                    .padding(.leading, 32)
            }

            if showOutputDetails, let verification = job.outputReport, verification.score > 0 {
                RiskDetailList(report: verification)
                    .padding(.leading, 32)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var verificationBadge: some View {
        if let verification = job.outputReport {
            if verification.score == 0 {
                Label("Ausgabe geprüft", systemImage: "checkmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .help("Die bereinigte Datei wurde erneut analysiert: keine aktiven Elemente.")
            } else {
                Button {
                    showOutputDetails.toggle()
                } label: {
                    Label("Prüfung: \(verification.score)", systemImage: "exclamationmark.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Unerwartet: Die Nachprüfung der Ausgabe hat Funde — klicken für Details.")
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .waiting:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var statusText: String {
        switch job.status {
        case .waiting:
            return "Wartet …"
        case .running(let page, let count):
            return "Seite \(page) von \(count) wird bereinigt …"
        case .done(let output):
            return "Fertig: \(output.lastPathComponent)"
        case .failed(let message):
            return message
        }
    }
}

// MARK: - Risk views

func riskColor(score: Int) -> Color {
    switch score {
    case 0: return .green
    case 1..<20: return .yellow
    case 20..<40: return .orange
    default: return .red
    }
}

struct RiskBadge: View {
    let report: RiskReport
    @Binding var expanded: Bool

    var body: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(riskColor(score: report.score))
                    .frame(width: 9, height: 9)
                Text("Risiko \(report.score)")
                    .font(.caption.weight(.semibold))
                Text("(\(report.levelLabel))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !report.findings.isEmpty {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(riskColor(score: report.score).opacity(0.15)))
        }
        .buttonStyle(.plain)
        .help("Analyse der Originaldatei — klicken für Details")
        .disabled(report.findings.isEmpty)
    }
}

struct RiskDetailList: View {
    let report: RiskReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(report.sortedFindings) { finding in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(finding.severity.label)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 4).fill(severityColor(finding.severity).opacity(0.2)))
                                .foregroundStyle(severityColor(finding.severity))
                            Text(finding.title)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        if !finding.details.isEmpty {
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(Array(finding.details.enumerated()), id: \.offset) { _, detail in
                                    Text(detail)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .textSelection(.enabled)
                            .padding(.leading, 8)
                        }
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 280)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }

    private func severityColor(_ severity: RiskFinding.Severity) -> Color {
        switch severity {
        case .info: return .blue
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
}