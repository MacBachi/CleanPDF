// CleanPDF — turn untrusted PDFs into guaranteed-passive, safe PDFs.
// Copyright (C) 2026 CleanPDF contributors
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. This program is distributed WITHOUT ANY WARRANTY; see
// the GNU General Public License <https://www.gnu.org/licenses/> for details.

import SwiftUI
import AppKit

// MARK: - Navigation

/// Which help page is shown; shared so menus and buttons can deep-link.
@MainActor
final class HelpNavigator: ObservableObject {
    static let shared = HelpNavigator()
    static let windowID = "help"

    @Published var selection: HelpTopicID? = .overview
    @Published var query = ""

    func show(_ topic: HelpTopicID) {
        query = ""
        selection = topic
    }
}

/// Opens the help window at a topic, from any view.
struct OpenHelp {
    let openWindow: OpenWindowAction

    @MainActor
    func callAsFunction(_ topic: HelpTopicID) {
        HelpNavigator.shared.show(topic)
        openWindow(id: HelpNavigator.windowID)
    }
}

extension View {
    /// Convenience for views: `openHelp(.riskScore)`.
    func helpButton(_ title: String, topic: HelpTopicID) -> some View {
        modifier(HelpButtonModifier(title: title, topic: topic))
    }
}

private struct HelpButtonModifier: ViewModifier {
    let title: String
    let topic: HelpTopicID
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content
            Button(title) { OpenHelp(openWindow: openWindow)(topic) }
                .buttonStyle(.link)
                .font(.caption)
        }
    }
}

// MARK: - Menu

struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("CleanPDF-Hilfe") { open(.overview) }
                .keyboardShortcut("?", modifiers: .command)
            Divider()
            Button("So funktioniert CleanPDF") { open(.howItWorks) }
            Button("Risiko-Score erklärt") { open(.riskScore) }
            Button("Häufige Fragen") { open(.faq) }
            Divider()
            Button("CleanPDF auf GitHub") { NSWorkspace.shared.open(HelpContent.repositoryURL) }
            Button("Problem melden …") { NSWorkspace.shared.open(HelpContent.issuesURL) }
        }
    }

    private func open(_ topic: HelpTopicID) {
        OpenHelp(openWindow: openWindow)(topic)
    }
}

// MARK: - Window

struct HelpView: View {
    @ObservedObject private var nav = HelpNavigator.shared

    private var results: [HelpTopic] { HelpContent.search(nav.query) }

    var body: some View {
        NavigationSplitView {
            List(results, selection: $nav.selection) { topic in
                Label(topic.title, systemImage: topic.symbol)
                    .tag(topic.id)
            }
            .overlay {
                if results.isEmpty {
                    Text("Keine Treffer")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            if let id = nav.selection, results.contains(where: { $0.id == id }) {
                ScrollView {
                    HelpTopicView(topic: HelpContent.topic(id))
                        .frame(maxWidth: 680, alignment: .leading)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 28)
                        .frame(maxWidth: .infinity)
                }
                // Every page starts at its title: without these the window
                // opened scrolled to the end, and switching topics kept the
                // previous page's scroll offset.
                .defaultScrollAnchor(.top)
                .id(id)
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                Text("Wähle links ein Thema.")
                    .foregroundStyle(.secondary)
            }
        }
        .searchable(text: $nav.query, placement: .sidebar, prompt: "Hilfe durchsuchen")
        .onChange(of: nav.query) {
            // Keep a visible page selected while searching.
            if let first = results.first, !results.contains(where: { $0.id == nav.selection }) {
                nav.selection = first.id
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}

// MARK: - Page

/// One help page. Contains no ScrollView, so it can also be rendered
/// off-screen (the test suite snapshots every page this way).
struct HelpTopicView: View {
    let topic: HelpTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(topic.title, systemImage: topic.symbol)
                .font(.largeTitle.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .padding(.bottom, 2)
            ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                HelpBlockView(block: block)
            }
        }
        .textSelection(.enabled)
    }
}

/// Inline Markdown (`**bold**`, `` `code` ``, links) as styled text.
func markdown(_ string: String) -> Text {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return Text((try? AttributedString(markdown: string, options: options)) ?? AttributedString(string))
}

struct HelpBlockView: View {
    let block: HelpBlock

    var body: some View {
        switch block {
        case .lead(let text):
            markdown(text)
                .font(.title3)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let text):
            Text(text)
                .font(.title2.weight(.semibold))
                .padding(.top, 10)
        case .paragraph(let text):
            markdown(text)
                .fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        markdown(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .steps(let steps):
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.callout.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.accentColor))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title).font(.headline)
                            markdown(step.text)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        case .note(let title, let text):
            Callout(symbol: "lightbulb", tint: .blue, title: title, text: text)
        case .warning(let title, let text):
            Callout(symbol: "exclamationmark.triangle", tint: .orange, title: title, text: text)
        case .code(let text):
            CodeBlock(text: text)
        case .question(let question, let answer):
            VStack(alignment: .leading, spacing: 4) {
                Text(question).font(.headline)
                markdown(answer)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        case .pipelineDiagram:
            PipelineDiagram()
        case .scoreLevels:
            ScoreLevelTable()
        case .severityTable:
            SeverityTable()
        }
    }
}

// MARK: - Components

private struct Callout: View {
    let symbol: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                markdown(text).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.25)))
    }
}

private struct CodeBlock: View {
    let text: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top) {
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Kopieren")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.10)))
    }
}

/// Original PDF → sandboxed worker → pixels → new PDF.
struct PipelineDiagram: View {
    private struct Node {
        let symbol: String
        let title: String
        let caption: String
        let tint: Color
        var sandboxed = false
    }

    private let nodes = [
        Node(symbol: "doc.fill", title: "Original-PDF", caption: "nicht vertrauenswürdig", tint: .orange),
        Node(symbol: "lock.shield.fill", title: "Hilfsprozess", caption: "abgeschottet: kein Internet, keine Dateien", tint: .indigo, sandboxed: true),
        Node(symbol: "square.grid.3x3.fill", title: "Nur Bildpunkte", caption: "von CleanPDF geprüft", tint: .teal),
        Node(symbol: "checkmark.seal.fill", title: "Neues PDF", caption: "+ Texterkennung, Gegenprobe", tint: .green),
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(Array(nodes.enumerated()), id: \.offset) { index, node in
                if index > 0 {
                    Image(systemName: "arrow.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 6) {
                    Image(systemName: node.symbol)
                        .font(.system(size: 26))
                        .foregroundStyle(node.tint)
                    Text(node.title)
                        .font(.callout.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(node.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 118)
                .background(RoundedRectangle(cornerRadius: 10).fill(node.tint.opacity(0.08)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(node.tint.opacity(node.sandboxed ? 0.8 : 0.25),
                                      style: StrokeStyle(lineWidth: node.sandboxed ? 2 : 1,
                                                         dash: node.sandboxed ? [5, 3] : []))
                )
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ablauf: Original-PDF, abgeschotteter Hilfsprozess, nur Bildpunkte, neues PDF")
    }
}

struct ScoreLevelTable: View {
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            ForEach(Array(RiskReport.levelBands.enumerated()), id: \.offset) { _, band in
                GridRow {
                    Circle()
                        .fill(riskColor(score: band.range.lowerBound))
                        .frame(width: 11, height: 11)
                    Text(band.range.lowerBound == band.range.upperBound
                         ? "\(band.range.lowerBound)"
                         : "\(band.range.lowerBound)–\(band.range.upperBound)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(band.label).fontWeight(.semibold)
                }
            }
        }
        .padding(.leading, 4)
    }
}

struct SeverityTable: View {
    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 10) {
            ForEach(RiskFinding.Severity.allCases.sorted(by: >), id: \.self) { severity in
                GridRow {
                    Text(severity.label)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(severityColor(severity).opacity(0.2)))
                        .foregroundStyle(severityColor(severity))
                    Text("\(severity.points) Punkte")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    // Take the remaining width instead of wrapping in a narrow column.
                    Text(HelpContent.severityExamples[severity] ?? "")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.leading, 4)
    }
}
