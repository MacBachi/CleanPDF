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
import CIsolation

/// One rendered page as received from the worker, already validated.
struct RenderedFrame {
    var pageNumber: Int
    var pointSize: CGSize
    var downscaled: Bool
    /// Built by the parent from raw pixels; the worker sends no image format.
    var image: CGImage
}

enum IsolationError: LocalizedError {
    case workerUnavailable(String)
    case sandboxUnavailable(String)
    case workerFailed(WorkerFailureCode, page: Int)
    case timedOut(page: Int)
    case memoryExceeded(page: Int, megabytes: Int)
    case protocolViolation(String)
    case crashed(status: Int32, page: Int)

    /// True when the failure says something about this machine, not the file.
    var isEnvironmentProblem: Bool {
        switch self {
        case .workerUnavailable, .sandboxUnavailable: return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .workerUnavailable(let why):
            return "Hilfsprozess konnte nicht gestartet werden: \(why)"
        case .sandboxUnavailable(let why):
            return "Sandbox nicht verfügbar – Datei wurde aus Sicherheitsgründen nicht verarbeitet (\(why))."
        case .workerFailed(let code, let page):
            switch code {
            case .cannotOpen: return "Datei konnte nicht als PDF geöffnet werden."
            case .encrypted: return "PDF ist passwortgeschützt. Bitte zuerst entsperren (z. B. in Vorschau exportieren)."
            case .noPages: return "PDF enthält keine Seiten."
            case .renderFailed: return "Seite \(page) konnte nicht gerendert werden."
            case .inputTooLarge: return "Datei ist zu groß (Grenze: 2 GB)."
            case .sandboxUnavailable: return "Sandbox nicht verfügbar."
            case .internalError: return "Interner Fehler im Hilfsprozess."
            }
        case .timedOut(let page):
            return "Zeitüberschreitung bei Seite \(page) – Verarbeitung abgebrochen (möglicherweise manipulierte Datei)."
        case .memoryExceeded(let page, let mb):
            return "Speichergrenze (\(mb) MB) bei Seite \(page) überschritten – Verarbeitung abgebrochen (möglicherweise manipulierte Datei)."
        case .protocolViolation(let what):
            return "Ungültige Antwort des Hilfsprozesses (\(what)) – Verarbeitung abgebrochen."
        case .crashed(let status, let page):
            return "Hilfsprozess bei Seite \(page) abgestürzt (Status \(status)) – beschädigte oder manipulierte Datei möglich."
        }
    }
}

/// Parent side of the isolation boundary: every parse of an untrusted PDF
/// happens in a sandboxed `Worker` child; this side only validates what
/// comes back.
enum IsolatedPDF {

    /// Seconds without any message from the worker before it is killed.
    static var pageTimeout: TimeInterval {
        envNumber("CLEANPDF_PAGE_TIMEOUT").map { max(1, $0) } ?? 120
    }

    /// Physical memory ceiling for the worker.
    static var memoryLimitMB: Int {
        envNumber("CLEANPDF_WORKER_MEMORY_MB").map { max(64, Int($0)) } ?? 3072
    }

    private static func envNumber(_ name: String) -> Double? {
        ProcessInfo.processInfo.environment[name].flatMap(Double.init)
    }

    /// Renders every page of `input` in the sandbox, handing validated frames
    /// to `onPage` in page order.
    static func render(
        input: URL,
        dpi: CGFloat,
        onPageCount: (Int) -> Void,
        onPage: (RenderedFrame) throws -> Void
    ) throws {
        let session = try WorkerSession(mode: ["render", String(Double(dpi))], input: input)
        defer { session.finish() }
        let reader = session.reader

        var expectedPages: Int?
        var nextPage = 1
        while true {
            switch try session.guarded({ try reader.tag() }) {
            case .pageCount:
                let count = Int(try reader.u32())
                guard expectedPages == nil, count > 0 else { throw IsolationError.protocolViolation("Seitenzahl") }
                expectedPages = count
                onPageCount(count)
            case .page:
                guard let total = expectedPages, nextPage <= total else {
                    throw IsolationError.protocolViolation("unerwartete Seite")
                }
                let frame = try session.guarded { try readFrame(reader, expectedPage: nextPage) }
                // The worker is blocked while the parent works on this page
                // (OCR can take a while), so that time must not count
                // against the worker's timeout.
                try session.parentWork { try onPage(frame) }
                nextPage += 1
                session.progress(page: nextPage)
            case .failure:
                throw try readFailure(reader)
            case .done:
                guard let total = expectedPages, nextPage == total + 1 else {
                    throw IsolationError.protocolViolation("vorzeitiges Ende")
                }
                try session.expectCleanExit()
                return
            case .json:
                throw IsolationError.protocolViolation("unerwartete Nachricht")
            }
        }
    }

    /// Runs the risk analysis in the sandbox.
    static func analyze(input: URL) throws -> RiskReport {
        let session = try WorkerSession(mode: ["analyze"], input: input)
        defer { session.finish() }
        let reader = session.reader
        switch try session.guarded({ try reader.tag() }) {
        case .json:
            let length = Int(try reader.u32())
            guard length <= WireLimits.maxJSONBytes else { throw IsolationError.protocolViolation("Bericht zu groß") }
            let json = try session.guarded { try reader.bytes(length) }
            guard var report = try? JSONDecoder().decode(RiskReport.self, from: json) else {
                throw IsolationError.protocolViolation("Bericht unlesbar")
            }
            report.clampForDisplay()
            guard try reader.tag() == .done else { throw IsolationError.protocolViolation("Ende fehlt") }
            try session.expectCleanExit()
            return report
        case .failure:
            throw try readFailure(reader)
        default:
            throw IsolationError.protocolViolation("unerwartete Nachricht")
        }
    }

    /// Analysis that never throws: a failed or aborted analysis becomes a
    /// finding, because a parser that dies on a file is itself a signal.
    static func analyzeReport(input: URL) -> RiskReport {
        do {
            return try analyze(input: input)
        } catch let error as IsolationError where error.isEnvironmentProblem {
            // Not the file's fault: say plainly that nothing was analysed.
            return RiskReport(findings: [RiskFinding(
                severity: .medium,
                title: "Analyse nicht durchgeführt",
                details: [error.localizedDescription])])
        } catch IsolationError.workerFailed(.cannotOpen, _) {
            return RiskReport(findings: [RiskFinding(
                severity: .medium,
                title: "Datei konnte nicht als PDF geparst werden",
                details: ["Struktur-Analyse nicht möglich."])])
        } catch {
            return RiskReport(findings: [RiskFinding(
                severity: .medium,
                title: "Analyse im abgeschotteten Hilfsprozess abgebrochen",
                details: [error.localizedDescription,
                          "Beschädigte oder gezielt manipulierte Datei möglich."])])
        }
    }

    // MARK: Validation

    static func readFrame(_ reader: WireReader, expectedPage: Int) throws -> RenderedFrame {
        let number = Int(try reader.u32())
        let width = try reader.f64()
        let height = try reader.f64()
        let pxW = Int(try reader.u32())
        let pxH = Int(try reader.u32())
        let downscaled = try reader.u8()

        guard number == expectedPage else { throw IsolationError.protocolViolation("Seitenreihenfolge") }
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              width <= WireLimits.maxPagePoints, height <= WireLimits.maxPagePoints else {
            throw IsolationError.protocolViolation("Seitenmaße")
        }
        guard pxW >= 1, pxH >= 1,
              Double(max(pxW, pxH)) <= RenderBudget.maxSide.rounded(.up),
              Double(pxW) * Double(pxH) <= RenderBudget.maxPixels * 1.01,
              downscaled <= 1 else {
            throw IsolationError.protocolViolation("Bildmaße außerhalb des Budgets")
        }

        let pixels = try reader.bytes(pxW * pxH * 4)
        // noneSkipLast: the alpha byte is ignored, so the worker can't smuggle
        // transparency; the page is always opaque.
        guard let provider = CGDataProvider(data: pixels as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: pxW, height: pxH, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: pxW * 4, space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw IsolationError.protocolViolation("Pixeldaten") }

        return RenderedFrame(pageNumber: number,
                             pointSize: CGSize(width: width, height: height),
                             downscaled: downscaled == 1,
                             image: image)
    }

    static func readFailure(_ reader: WireReader) throws -> IsolationError {
        let code = WorkerFailureCode(rawValue: try reader.u8()) ?? .internalError
        let page = Int(try reader.u32())
        let length = Int(try reader.u16())
        guard length <= WireLimits.maxMessageBytes else { return .protocolViolation("Fehlermeldung zu lang") }
        let message = String(decoding: try reader.bytes(length), as: UTF8.self)
        if code == .sandboxUnavailable { return .sandboxUnavailable(message) }
        return .workerFailed(code, page: page)
    }
}

// MARK: - Worker process management

/// One worker child: launches it, feeds the input file to its stdin, and
/// kills it if it stalls or exceeds the memory ceiling.
final class WorkerSession {
    let reader: WireReader
    private let process = Process()
    private let lock = NSLock()
    private var lastActivity = Date()
    private var currentPage = 1
    private var parentBusy = false
    private var killReason: IsolationError?
    private var watchdog: DispatchSourceTimer?
    private let timeout = IsolatedPDF.pageTimeout
    private let memoryLimitBytes = Int64(IsolatedPDF.memoryLimitMB) * 1024 * 1024

    init(mode: [String], input: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: input.path)
        if let size = attributes[.size] as? Int, size > WireLimits.maxInputBytes {
            throw IsolationError.workerFailed(.inputTooLarge, page: 0)
        }
        let inputHandle = try FileHandle(forReadingFrom: input)

        guard let executable = Bundle.main.executableURL else {
            throw IsolationError.workerUnavailable("eigene Programmdatei nicht gefunden")
        }
        let stdinPipe = Pipe(), stdoutPipe = Pipe()
        process.executableURL = executable
        process.arguments = ["--worker"] + mode
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw IsolationError.workerUnavailable(error.localizedDescription)
        }
        reader = WireReader(fd: stdoutPipe.fileHandleForReading.fileDescriptor)

        // Feed the file in the background; a worker that dies early just
        // ends the copy (EPIPE surfaces as a thrown error, SIGPIPE is ignored).
        let sink = stdinPipe.fileHandleForWriting
        DispatchQueue.global(qos: .userInitiated).async {
            defer { try? sink.close(); try? inputHandle.close() }
            while let chunk = try? inputHandle.read(upToCount: 1 << 20), !chunk.isEmpty {
                if (try? sink.write(contentsOf: chunk)) == nil { return }
            }
        }
        startWatchdog()
    }

    /// Records that page `page` is now being rendered (resets the timeout).
    func progress(page: Int) {
        lock.lock(); lastActivity = Date(); currentPage = page; lock.unlock()
    }

    /// Runs parent-side work during which the worker's timeout is paused.
    func parentWork(_ body: () throws -> Void) throws {
        lock.lock(); parentBusy = true; lock.unlock()
        defer { lock.lock(); parentBusy = false; lastActivity = Date(); lock.unlock() }
        try body()
    }

    /// Runs a blocking read; if the watchdog killed the worker meanwhile,
    /// reports why instead of a generic short read.
    func guarded<T>(_ body: () throws -> T) throws -> T {
        do {
            let value = try body()
            lock.lock(); lastActivity = Date(); lock.unlock()
            return value
        } catch {
            throw failureReason(default: error)
        }
    }

    func expectCleanExit() throws {
        process.waitUntilExit()
        if process.terminationReason != .exit || process.terminationStatus != 0 {
            throw failureReason(default: IsolationError.crashed(status: process.terminationStatus, page: page))
        }
    }

    func finish() {
        watchdog?.cancel()
        if process.isRunning { process.terminate() }
    }

    private var page: Int { lock.lock(); defer { lock.unlock() }; return currentPage }

    private func failureReason(default error: Error) -> Error {
        lock.lock(); let reason = killReason; lock.unlock()
        if let reason { return reason }
        if case WireReader.ReadError.endOfStream = error {
            process.waitUntilExit()
            return IsolationError.crashed(status: process.terminationStatus, page: page)
        }
        return error
    }

    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        let pid = process.processIdentifier
        timer.setEventHandler { [weak self] in
            guard let self, self.process.isRunning else { return }
            self.lock.lock()
            let idle = Date().timeIntervalSince(self.lastActivity)
            let page = self.currentPage
            let busy = self.parentBusy
            self.lock.unlock()

            var reason: IsolationError?
            if !busy && idle > self.timeout {
                reason = .timedOut(page: page)
            } else {
                let footprint = cleanpdf_phys_footprint(pid)
                if footprint > self.memoryLimitBytes {
                    reason = .memoryExceeded(page: page, megabytes: Int(self.memoryLimitBytes / 1_048_576))
                }
            }
            guard let reason else { return }
            self.lock.lock()
            if self.killReason == nil { self.killReason = reason }
            self.lock.unlock()
            kill(pid, SIGKILL)
        }
        timer.resume()
        watchdog = timer
    }
}

/// Blocking little-endian reader over the worker's stdout.
final class WireReader {
    enum ReadError: Error { case endOfStream }
    private let fd: Int32

    init(fd: Int32) { self.fd = fd }

    func tag() throws -> WireTag {
        let raw = try u8()
        guard let tag = WireTag(rawValue: raw) else { throw IsolationError.protocolViolation("unbekannte Nachricht") }
        return tag
    }
    func u8() throws -> UInt8 { try bytes(1)[0] }
    func u16() throws -> UInt16 { UInt16(littleEndian: try fixed()) }
    func u32() throws -> UInt32 { UInt32(littleEndian: try fixed()) }
    func f64() throws -> Double { Double(bitPattern: UInt64(littleEndian: try fixed())) }

    private func fixed<T: FixedWidthInteger>() throws -> T {
        let data = try bytes(MemoryLayout<T>.size)
        return data.withUnsafeBytes { $0.loadUnaligned(as: T.self) }
    }

    /// Reads exactly `count` bytes.
    func bytes(_ count: Int) throws -> Data {
        var data = Data(count: count)
        var filled = 0
        try data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            while filled < count {
                let n = read(fd, base + filled, count - filled)
                if n > 0 {
                    filled += n
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    throw ReadError.endOfStream
                }
            }
        }
        return data
    }
}
