// CleanPDF — turn untrusted PDFs into guaranteed-passive, safe PDFs.
// Copyright (C) 2026 CleanPDF contributors
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. This program is distributed WITHOUT ANY WARRANTY; see
// the GNU General Public License <https://www.gnu.org/licenses/> for details.

import XCTest
@testable import CleanPDF

final class RenderBudgetTests: XCTestCase {

    func testNormalPageKeepsRequestedResolution() {
        let scale = RenderBudget.scale(for: CGSize(width: 595, height: 842), dpi: 300)
        XCTAssertEqual(scale!, 300 / 72, accuracy: 1e-9)
    }

    func testOversizedPageStaysWithinPixelBudget() {
        let size = CGSize(width: 14400, height: 14400)
        let scale = RenderBudget.scale(for: size, dpi: 200)!
        let pixels = Double(size.width * scale) * Double(size.height * scale)
        XCTAssertLessThanOrEqual(pixels, RenderBudget.maxPixels * 1.0001)
        XCTAssertLessThan(scale, 200 / 72)
    }

    func testElongatedPageStaysWithinSideLimit() {
        let size = CGSize(width: 14400, height: 10)
        let scale = RenderBudget.scale(for: size, dpi: 600)!
        XCTAssertLessThanOrEqual(Double(size.width * scale), RenderBudget.maxSide + 0.5)
    }

    func testDegenerateSizesAreRefused() {
        XCTAssertNil(RenderBudget.scale(for: CGSize(width: 0, height: 100), dpi: 200))
        XCTAssertNil(RenderBudget.scale(for: CGSize(width: -1, height: 100), dpi: 200))
        XCTAssertNil(RenderBudget.scale(for: CGSize(width: CGFloat.nan, height: 100), dpi: 200))
        XCTAssertNil(RenderBudget.scale(for: CGSize(width: CGFloat.infinity, height: 100), dpi: 200))
        XCTAssertNil(RenderBudget.scale(for: CGSize(width: 100, height: 100), dpi: 0))
    }
}

final class RiskReportTests: XCTestCase {

    func testReportRoundTripsThroughJSON() throws {
        let report = RiskReport(findings: [
            RiskFinding(severity: .critical, title: "JS", details: ["app.alert(1)"]),
            RiskFinding(severity: .info, title: "JBIG2"),
        ])
        let decoded = try JSONDecoder().decode(RiskReport.self, from: JSONEncoder().encode(report))
        XCTAssertEqual(decoded.score, report.score)
        XCTAssertEqual(decoded.findings.map(\.title), ["JS", "JBIG2"])
        XCTAssertEqual(decoded.findings.first?.details, ["app.alert(1)"])
    }

    func testHostileReportIsClampedForDisplay() {
        var report = RiskReport(findings: (0..<1000).map { _ in
            RiskFinding(severity: .medium,
                        title: String(repeating: "T", count: 10_000),
                        details: Array(repeating: String(repeating: "D", count: 50_000), count: 1000))
        })
        report.clampForDisplay()
        XCTAssertLessThanOrEqual(report.findings.count, 200)
        XCTAssertLessThanOrEqual(report.findings.map(\.title.count).max()!, 300)
        XCTAssertLessThanOrEqual(report.findings.map(\.details.count).max()!, 150)
        XCTAssertLessThanOrEqual(report.findings.flatMap(\.details).map(\.count).max()!, 2000)
    }

    func testScoreIsCappedAt100() {
        let report = RiskReport(findings: Array(repeating: RiskFinding(severity: .critical, title: "x"), count: 10))
        XCTAssertEqual(report.score, 100)
    }
}
