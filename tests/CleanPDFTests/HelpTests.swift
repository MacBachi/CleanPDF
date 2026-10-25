// CleanPDF — turn untrusted PDFs into guaranteed-passive, safe PDFs.
// Copyright (C) 2026 CleanPDF contributors
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. This program is distributed WITHOUT ANY WARRANTY; see
// the GNU General Public License <https://www.gnu.org/licenses/> for details.

import XCTest
import Metal
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
@testable import CleanPDF

final class HelpContentTests: XCTestCase {

    func testEveryTopicExistsOnceWithContent() {
        let ids = HelpContent.topics.map(\.id)
        XCTAssertEqual(ids, HelpTopicID.allCases, "sidebar order must match HelpTopicID")
        for topic in HelpContent.topics {
            XCTAssertFalse(topic.title.isEmpty)
            XCTAssertGreaterThanOrEqual(topic.blocks.count, 3, "\(topic.id) is too thin")
        }
    }

    func testSearchFindsTheRightPages() {
        func ids(_ q: String) -> Set<HelpTopicID> { Set(HelpContent.search(q).map(\.id)) }
        XCTAssertEqual(HelpContent.search("").count, HelpTopicID.allCases.count)
        XCTAssertTrue(ids("Passwort").contains(.faq))
        XCTAssertTrue(ids("Sandbox").contains(.faq))
        XCTAssertTrue(ids("JavaScript").contains(.riskScore))
        XCTAssertTrue(ids("dpi").contains(.usage))
        XCTAssertTrue(ids("sandbox-selftest").contains(.commandLine))
        XCTAssertTrue(ids("JBIG2").contains(.riskScore), "severity examples must be searchable")
        XCTAssertTrue(ids("dennoch öffnen").contains(.faq), "multi-word, case-insensitive")
        XCTAssertTrue(ids("xyzzy-nichts").isEmpty)
    }

    func testScoreBandsCoverZeroToHundredWithoutGaps() {
        let bands = RiskReport.levelBands
        XCTAssertEqual(bands.first?.range.lowerBound, 0)
        XCTAssertEqual(bands.last?.range.upperBound, 100)
        for (a, b) in zip(bands, bands.dropFirst()) {
            XCTAssertEqual(a.range.upperBound + 1, b.range.lowerBound, "gap or overlap after \(a.label)")
        }
        // The label the app shows for a score is the one the help lists.
        for score in 0...100 {
            let band = bands.first { $0.range.contains(score) }!
            XCTAssertEqual(RiskReport.level(for: score), band.label)
        }
    }

    func testHelpQuotesTheLimitsTheCodeEnforces() {
        let text = HelpContent.topics.map(\.searchableText).joined(separator: " ")
        XCTAssertTrue(text.contains("\(Int(IsolatedPDF.defaultPageTimeout)) sekunden"))
        XCTAssertTrue(text.contains("\(IsolatedPDF.defaultMemoryLimitMB / 1024) gb"))
        XCTAssertTrue(text.contains("\(Int(RenderBudget.maxPixels / 1_000_000)) megapixel"))
        for severity in RiskFinding.Severity.allCases {
            XCTAssertNotNil(HelpContent.severityExamples[severity], "no example for \(severity)")
        }
    }

    func testInlineMarkdownParses() {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        for topic in HelpContent.topics {
            for string in Mirror.strings(in: topic) {
                XCTAssertNoThrow(try AttributedString(markdown: string, options: options),
                                 "bad markdown in \(topic.id): \(string.prefix(60))")
            }
        }
    }
}

/// Renders every help page off-screen. Fails if a page can't be laid out;
/// with HELP_SNAPSHOT_DIR set, also writes PNGs for visual review.
@MainActor
final class HelpRenderingTests: XCTestCase {

    /// ImageRenderer needs a real GPU. CI's Intel runner is a VM with a
    /// paravirtual Metal device, on which Metal aborts the process ("Target
    /// device architecture is nil"); skip there, visibly, rather than crash.
    private func requireRealGPU() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device")
        }
        if device.name.localizedCaseInsensitiveContains("paravirtual") || device.architecture.name.isEmpty {
            throw XCTSkip("virtual GPU (\(device.name)) cannot render off-screen")
        }
    }

    func testEveryPageRendersInLightAndDarkMode() throws {
        try requireRealGPU()
        let dir = ProcessInfo.processInfo.environment["HELP_SNAPSHOT_DIR"]
        for topic in HelpContent.topics {
            for scheme in [ColorScheme.light, .dark] {
                let page = HelpTopicView(topic: topic)
                    .frame(width: 680, alignment: .leading)
                    .padding(28)
                    .background(scheme == .dark ? Color.black : Color.white)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: page)
                // Fixed width, free height: lay out like the scrolling help window.
                renderer.proposedSize = ProposedViewSize(width: 736, height: nil)
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.cgImage, "\(topic.id) did not render")
                XCTAssertGreaterThan(image.height, 200, "\(topic.id) rendered nearly empty")

                if let dir {
                    let url = URL(fileURLWithPath: dir).appendingPathComponent("\(topic.id)-\(scheme == .dark ? "dark" : "light").png")
                    let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
                    CGImageDestinationAddImage(dest, image, nil)
                    XCTAssertTrue(CGImageDestinationFinalize(dest))
                }
            }
        }
    }
}

private enum Mirror {
    /// All strings shown on a help page.
    static func strings(in topic: HelpTopic) -> [String] {
        topic.blocks.flatMap { block -> [String] in
            switch block {
            case .lead(let s), .heading(let s), .paragraph(let s), .code(let s): return [s]
            case .bullets(let items): return items
            case .steps(let steps): return steps.flatMap { [$0.title, $0.text] }
            case .note(let t, let s), .warning(let t, let s): return [t, s]
            case .question(let q, let a): return [q, a]
            case .pipelineDiagram, .scoreLevels, .severityTable: return []
            }
        }
    }
}
