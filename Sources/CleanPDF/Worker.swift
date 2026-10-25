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

/// The sandboxed child process that touches untrusted PDFs.
///
/// Started by the parent as `CleanPDF --worker <render|analyze> [dpi]`. The
/// very first thing it does is lock itself into `Worker.sandboxProfile`;
/// only then does it read the PDF from stdin. It answers on stdout using
/// the wire format in WorkerProtocol.swift. If the sandbox cannot be applied
/// it refuses to work (fail closed) rather than parse the file unprotected.
enum Worker {

    /// Deny everything, then allow only reading system code, fonts and colour
    /// profiles that the renderer may load lazily. No network (including DNS
    /// and localhost), no reading user files, no writing anywhere, no
    /// launching processes, no IPC to system services. The pipes inherited
    /// from the parent are already open and keep working.
    static let sandboxProfile = """
    (version 1)
    (deny default)
    (allow file-read*
        (subpath "/System")
        (subpath "/usr/lib")
        (subpath "/usr/share")
        (subpath "/Library/Fonts")
        (subpath "/Library/ColorSync"))
    (allow sysctl-read)
    """

    /// CPU-time ceiling enforced by the kernel, independent of the parent's
    /// wall-clock watchdog.
    static let cpuSecondsLimit: UInt64 = 1800

    static func main(arguments: [String]) -> Int32 {
        cleanpdf_limit_worker_resources(cpuSecondsLimit)
        exitWhenOrphaned()
        prepareForSandbox()

        if let message = enterSandbox() {
            send(failure: .sandboxUnavailable, page: 0, message: message)
            return 3
        }

        guard let mode = arguments.first else {
            send(failure: .internalError, page: 0, message: "missing worker mode")
            return 2
        }
        guard let input = readAllStdin(limit: WireLimits.maxInputBytes) else {
            send(failure: .inputTooLarge, page: 0, message: "input exceeds limit")
            return 2
        }

        switch mode {
        case "render":
            let dpi = arguments.count > 1 ? Double(arguments[1]) ?? 200 : 200
            return render(input, dpi: CGFloat(dpi))
        case "analyze":
            return analyze(input)
        default:
            send(failure: .internalError, page: 0, message: "unknown worker mode")
            return 2
        }
    }

    /// If the parent goes away (app quit, CLI interrupted), a worker busy on
    /// a slow page would otherwise keep computing until its next write.
    /// Orphans are re-parented to launchd, so a changed parent pid means
    /// nobody is waiting for the result.
    static func exitWhenOrphaned() {
        let parent = getppid()
        Thread.detachNewThread {
            while true {
                sleep(1)
                if getppid() != parent { _exit(4) }
            }
        }
    }

    /// Loads, from trusted sources only, what system frameworks would
    /// otherwise try to read from disk after the sandbox is closed.
    ///
    /// ImageIO consults the main bundle's Info.plist the first time it decodes
    /// an image (to decide on out-of-process decoding). Our own executable
    /// lives outside the paths the sandbox may read, and CoreFoundation
    /// crashes rather than failing cleanly when that lookup is denied — so
    /// every JPEG in a PDF killed the worker. Loading the dictionary here
    /// caches it.
    static func prepareForSandbox() {
        _ = CFBundleGetInfoDictionary(CFBundleGetMainBundle())
    }

    /// Applies the sandbox; returns an error message on failure.
    static func enterSandbox() -> String? {
        var error: UnsafeMutablePointer<CChar>?
        if cleanpdf_apply_sandbox(sandboxProfile, &error) == 0 {
            return nil
        }
        defer { free(error) }
        return error.map { String(cString: $0) } ?? "sandbox_init failed"
    }

    // MARK: Modes

    private static func render(_ input: Data, dpi: CGFloat) -> Int32 {
        guard let provider = CGDataProvider(data: input as CFData),
              let doc = CGPDFDocument(provider) else {
            send(failure: .cannotOpen, page: 0, message: "")
            return 1
        }
        if doc.isEncrypted && !doc.unlockWithPassword("") {
            send(failure: .encrypted, page: 0, message: "")
            return 1
        }
        let pageCount = doc.numberOfPages
        guard pageCount > 0 else {
            send(failure: .noPages, page: 0, message: "")
            return 1
        }

        var header = WireWriter()
        header.tag(.pageCount)
        header.u32(UInt32(pageCount))
        guard write(header.data) else { return 1 }

        for pageNumber in 1...pageCount {
            guard let page = doc.page(at: pageNumber),
                  sendPage(page, number: pageNumber, dpi: dpi) else {
                send(failure: .renderFailed, page: pageNumber, message: "")
                return 1
            }
        }
        var done = WireWriter()
        done.tag(.done)
        return write(done.data) ? 0 : 1
    }

    private static func analyze(_ input: Data) -> Int32 {
        let report = RiskAnalyzer.analyze(data: input)
        guard let json = try? JSONEncoder().encode(report) else {
            send(failure: .internalError, page: 0, message: "encoding failed")
            return 1
        }
        var msg = WireWriter()
        msg.tag(.json)
        msg.u32(UInt32(json.count))
        msg.bytes(json)
        msg.tag(.done)
        return write(msg.data) ? 0 : 1
    }

    // MARK: Rendering

    /// Effective page size in points, accounting for /Rotate.
    static func pageSize(of page: CGPDFPage) -> CGSize {
        let crop = page.getBoxRect(.cropBox)
        let rotated = abs(page.rotationAngle) % 180 == 90
        return CGSize(width: rotated ? crop.height : crop.width,
                      height: rotated ? crop.width : crop.height)
    }

    /// Renders one page within the render budget and streams it to stdout.
    private static func sendPage(_ page: CGPDFPage, number: Int, dpi: CGFloat) -> Bool {
        let pointSize = pageSize(of: page)
        guard let scale = RenderBudget.scale(for: pointSize, dpi: dpi) else { return false }
        let downscaled = scale < dpi / 72.0 * 0.999
        let width = max(1, Int((pointSize.width * scale).rounded()))
        let height = max(1, Int((pointSize.height * scale).rounded()))

        // Tightly packed rows, so the bitmap memory can be sent as-is.
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmap = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = bitmap.data
        else { return false }

        bitmap.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
        bitmap.interpolationQuality = .high
        // getDrawingTransform never scales up, so apply the dpi scale ourselves
        // and let the transform handle only rotation and crop-box origin.
        bitmap.scaleBy(x: scale, y: scale)
        let pointRect = CGRect(origin: .zero, size: pointSize)
        bitmap.concatenate(page.getDrawingTransform(.cropBox, rect: pointRect, rotate: 0, preserveAspectRatio: true))
        bitmap.drawPDFPage(page)

        var header = WireWriter()
        header.tag(.page)
        header.u32(UInt32(number))
        header.f64(Double(pointSize.width))
        header.f64(Double(pointSize.height))
        header.u32(UInt32(width))
        header.u32(UInt32(height))
        header.u8(downscaled ? 1 : 0)
        let body = Data(bytesNoCopy: pixels, count: width * height * 4, deallocator: .none)
        return write(header.data) && write(body)
    }

    // MARK: I/O

    private static func readAllStdin(limit: Int) -> Data? {
        var data = Data()
        let handle = FileHandle.standardInput
        while true {
            guard let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty else { break }
            data.append(chunk)
            if data.count > limit { return nil }
        }
        return data
    }

    @discardableResult
    private static func write(_ data: Data) -> Bool {
        (try? FileHandle.standardOutput.write(contentsOf: data)) != nil
    }

    private static func send(failure code: WorkerFailureCode, page: Int, message: String) {
        let text = Data(message.utf8.prefix(WireLimits.maxMessageBytes))
        var msg = WireWriter()
        msg.tag(.failure)
        msg.u8(code.rawValue)
        msg.u32(UInt32(clamping: page))
        msg.u16(UInt16(text.count))
        msg.bytes(text)
        write(msg.data)
    }
}

// MARK: - Self-test

extension Worker {
    /// `CleanPDF --sandbox-selftest <file-to-read> <dir-to-write>`: enters the
    /// worker sandbox in this process and checks that the operations it must
    /// forbid really fail. Exit code 0 only if every check is blocked.
    static func selfTest(arguments: [String]) -> Int32 {
        guard arguments.count >= 2 else {
            print("usage: CleanPDF --sandbox-selftest <file-to-read> <dir-to-write>")
            return 2
        }
        if let message = enterSandbox() {
            print("sandbox: UNAVAILABLE (\(message))")
            return 1
        }
        print("sandbox: applied")

        var allBlocked = true
        func report(_ name: String, blocked: Bool, _ detail: String) {
            print("\(name): \(blocked ? "blocked" : "ALLOWED") (\(detail))")
            if !blocked { allBlocked = false }
        }
        func errorText() -> String { String(cString: strerror(errno)) }

        let readFD = open(arguments[0], O_RDONLY)
        report("read-user-file", blocked: readFD < 0, readFD < 0 ? errorText() : "opened")
        if readFD >= 0 { close(readFD) }

        let target = arguments[1] + "/cleanpdf-selftest-\(getpid())"
        let writeFD = open(target, O_CREAT | O_WRONLY, 0o600)
        report("write-file", blocked: writeFD < 0, writeFD < 0 ? errorText() : "created")
        if writeFD >= 0 { close(writeFD) }

        // Localhost, closed port: EPERM means the sandbox refused; anything
        // else (e.g. ECONNREFUSED) means the connection was attempted.
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(9).bigEndian
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)
        let connected = sock < 0 ? -1 : withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        let connectErrno = errno
        report("network-connect",
               blocked: sock < 0 || (connected != 0 && connectErrno == EPERM),
               sock < 0 ? errorText() : String(cString: strerror(connectErrno)))
        if sock >= 0 { close(sock) }

        var resolved: UnsafeMutablePointer<addrinfo>?
        let lookup = getaddrinfo("example.com", "80", nil, &resolved)
        report("dns-lookup", blocked: lookup != 0, lookup != 0 ? String(cString: gai_strerror(lookup)) : "resolved")
        if let resolved { freeaddrinfo(resolved) }

        var pid: pid_t = 0
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup("/usr/bin/true"), nil]
        let spawned = posix_spawn(&pid, "/usr/bin/true", nil, nil, argv, environ)
        report("spawn-process", blocked: spawned != 0, spawned != 0 ? String(cString: strerror(spawned)) : "started")

        print(allBlocked ? "result: all blocked" : "result: NOT ISOLATED")
        return allBlocked ? 0 : 1
    }
}
