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

/// The parent must treat everything from the worker as hostile. These tests
/// play a compromised worker: they push crafted bytes through a real pipe
/// into the parent's validation and check that anything out of bounds is
/// rejected before it is used.
final class WireValidationTests: XCTestCase {

    /// Writes `bytes` into a pipe, closes it, and returns a reader on it.
    private func reader(for bytes: Data) -> (WireReader, Pipe) {
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(bytes)
        try? pipe.fileHandleForWriting.close()
        return (WireReader(fd: pipe.fileHandleForReading.fileDescriptor), pipe)
    }

    /// A page frame body (everything after the 'P' tag).
    private func frame(page: UInt32 = 1, width: Double = 612, height: Double = 792,
                       pxW: UInt32 = 4, pxH: UInt32 = 3, downscaled: UInt8 = 0,
                       pixelBytes: Int? = nil) -> Data {
        var w = WireWriter()
        w.u32(page); w.f64(width); w.f64(height); w.u32(pxW); w.u32(pxH); w.u8(downscaled)
        w.bytes(Data(repeating: 0x80, count: pixelBytes ?? Int(pxW) * Int(pxH) * 4))
        return w.data
    }

    private func assertViolation(_ body: Data, expectedPage: Int = 1,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let (r, pipe) = reader(for: body)
        XCTAssertThrowsError(try IsolatedPDF.readFrame(r, expectedPage: expectedPage), file: file, line: line) { error in
            guard case IsolationError.protocolViolation = error else {
                return XCTFail("expected protocolViolation, got \(error)", file: file, line: line)
            }
        }
        _ = pipe
    }

    func testValidFrameIsAccepted() throws {
        let (r, pipe) = reader(for: frame())
        let f = try IsolatedPDF.readFrame(r, expectedPage: 1)
        XCTAssertEqual(f.pageNumber, 1)
        XCTAssertEqual(f.pointSize, CGSize(width: 612, height: 792))
        XCTAssertEqual(f.image.width, 4)
        XCTAssertEqual(f.image.height, 3)
        XCTAssertFalse(f.downscaled)
        _ = pipe
    }

    func testAlphaFromWorkerIsIgnored() throws {
        let (r, pipe) = reader(for: frame())
        let f = try IsolatedPDF.readFrame(r, expectedPage: 1)
        XCTAssertEqual(f.image.alphaInfo, .noneSkipLast)
        _ = pipe
    }

    func testOutOfOrderPageIsRejected() {
        assertViolation(frame(page: 2), expectedPage: 1)
    }

    func testBadPageSizesAreRejected() {
        assertViolation(frame(width: .nan))
        assertViolation(frame(width: .infinity))
        assertViolation(frame(width: 0))
        assertViolation(frame(height: -10))
        assertViolation(frame(width: 2_000_000))
    }

    func testPixelSizesOverBudgetAreRejected() {
        // Header only: the parent must refuse before trying to read the pixels.
        assertViolation(frame(pxW: 30_000, pxH: 10, pixelBytes: 0))
        assertViolation(frame(pxW: 10_000, pxH: 10_000, pixelBytes: 0))
        assertViolation(frame(pxW: 0, pxH: 10, pixelBytes: 0))
        assertViolation(frame(pxW: UInt32.max, pxH: UInt32.max, pixelBytes: 0))
    }

    func testInvalidDownscaleFlagIsRejected() {
        assertViolation(frame(downscaled: 7))
    }

    func testTruncatedPixelDataEndsTheStream() {
        let (r, pipe) = reader(for: frame(pxW: 4, pxH: 3, pixelBytes: 20))
        XCTAssertThrowsError(try IsolatedPDF.readFrame(r, expectedPage: 1)) { error in
            guard case WireReader.ReadError.endOfStream = error else {
                return XCTFail("expected endOfStream, got \(error)")
            }
        }
        _ = pipe
    }

    func testUnknownTagIsRejected() {
        let (r, pipe) = reader(for: Data([0x5A]))
        XCTAssertThrowsError(try r.tag()) { error in
            guard case IsolationError.protocolViolation = error else {
                return XCTFail("expected protocolViolation, got \(error)")
            }
        }
        _ = pipe
    }

    func testOversizedFailureMessageIsRejected() throws {
        var w = WireWriter()
        w.u8(WorkerFailureCode.renderFailed.rawValue); w.u32(3); w.u16(UInt16.max)
        let (r, pipe) = reader(for: w.data)
        guard case .protocolViolation = try IsolatedPDF.readFailure(r) else {
            return XCTFail("oversized failure message accepted")
        }
        _ = pipe
    }

    func testUnknownFailureCodeMapsToInternalError() throws {
        var w = WireWriter()
        w.u8(250); w.u32(1); w.u16(0)
        let (r, pipe) = reader(for: w.data)
        guard case .workerFailed(.internalError, _) = try IsolatedPDF.readFailure(r) else {
            return XCTFail("unknown failure code not mapped to internalError")
        }
        _ = pipe
    }
}
