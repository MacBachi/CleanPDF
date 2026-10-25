// CleanPDF — turn untrusted PDFs into guaranteed-passive, safe PDFs.
// Copyright (C) 2026 CleanPDF contributors
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. This program is distributed WITHOUT ANY WARRANTY; see
// the GNU General Public License <https://www.gnu.org/licenses/> for details.

import Foundation

/// Wire format from the sandboxed worker to the parent (worker's stdout).
///
/// Each message is a one-byte tag followed by little-endian fields:
///
///     N  u32 pageCount
///     P  u32 page, f64 widthPt, f64 heightPt, u32 pxW, u32 pxH, u8 downscaled,
///        then pxW * pxH * 4 bytes of RGBX pixels (alpha byte ignored)
///     J  u32 length, then that many bytes of JSON (analysis report)
///     F  u8 code, u32 page, u16 length, then a UTF-8 message
///     D  (done)
///
/// Raw pixels are deliberately the only image format: the parent never has
/// to decode anything the worker produced. Everything read from the worker
/// is untrusted and validated by `WorkerReader`.
enum WireTag: UInt8 {
    case pageCount = 0x4E  // N
    case page = 0x50       // P
    case json = 0x4A       // J
    case failure = 0x46    // F
    case done = 0x44       // D
}

/// Why the worker could not complete. Codes are part of the wire format.
enum WorkerFailureCode: UInt8 {
    case cannotOpen = 1
    case encrypted = 2
    case noPages = 3
    case renderFailed = 4
    case sandboxUnavailable = 5
    case inputTooLarge = 6
    case internalError = 7
}

/// Limits shared by both sides of the pipe.
enum WireLimits {
    /// Largest input PDF accepted.
    static let maxInputBytes = 2 * 1024 * 1024 * 1024
    /// Largest analysis report accepted.
    static let maxJSONBytes = 8 * 1024 * 1024
    /// Largest failure message accepted.
    static let maxMessageBytes = 2048
    /// Sanity bound on page dimensions in points (PDF caps pages at 14400 pt;
    /// /UserUnit can legitimately go beyond that).
    static let maxPagePoints: Double = 1_000_000
}

/// Little-endian encoder for worker → parent messages.
struct WireWriter {
    private(set) var data = Data()

    mutating func tag(_ tag: WireTag) { data.append(tag.rawValue) }
    mutating func u8(_ v: UInt8) { data.append(v) }
    mutating func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    mutating func f64(_ v: Double) { withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
    mutating func bytes(_ d: Data) { data.append(d) }
}
