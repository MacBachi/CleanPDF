// Render-parity check: does the sanitized output look like the original?
//
// Renders every page of the original PDF directly with CoreGraphics (in this
// test process, outside any sandbox) and the matching page of the sanitized
// PDF, both at the same size, and compares pixels. A font, image or shading
// that the sandboxed worker failed to draw shows up as a large local
// difference even when the page average looks fine.
//
// Both are compared at the resolution CleanPDF renders at (200 dpi). At a
// lower resolution, glyph and icon edges anti-alias differently when drawn
// as vectors versus scaled down from a bitmap, which reads as a false
// difference on small text and icons.
//
// Usage: swiftc -O tests/check_render_parity.swift -o parity && ./parity a.pdf b.pdf
// Prints one line per page and PARITY_OK if every page is within tolerance.
import CoreGraphics
import Foundation

let dpi = CGFloat(Double(ProcessInfo.processInfo.environment["PARITY_DPI"] ?? "") ?? 200)
let block = 16
/// Mean absolute difference over the page (0–255). JPEG noise is ~1–2.
let maxMeanDiff = 6.0
/// Worst 16x16 block. Missing glyphs or images push this far higher.
let maxBlockDiff = 60.0

func render(_ page: CGPDFPage) -> (pixels: [UInt8], w: Int, h: Int)? {
    let crop = page.getBoxRect(.cropBox)
    let rotated = abs(page.rotationAngle) % 180 == 90
    let size = CGSize(width: rotated ? crop.height : crop.width, height: rotated ? crop.width : crop.height)
    let scale = dpi / 72
    let w = max(1, Int((size.width * scale).rounded())), h = max(1, Int((size.height * scale).rounded()))
    guard w * h <= 40_000_000,
          let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: scale, y: scale)
    ctx.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size),
                                             rotate: 0, preserveAspectRatio: true))
    ctx.drawPDFPage(page)
    let ptr = ctx.data!.assumingMemoryBound(to: UInt8.self)
    return (Array(UnsafeBufferPointer(start: ptr, count: w * h * 4)), w, h)
}

let args = CommandLine.arguments
guard args.count >= 3,
      let a = CGPDFDocument(URL(fileURLWithPath: args[1]) as CFURL),
      let b = CGPDFDocument(URL(fileURLWithPath: args[2]) as CFURL) else {
    print("READ_FAILED"); exit(1)
}
guard a.numberOfPages == b.numberOfPages else {
    print("PAGE_COUNT_MISMATCH \(a.numberOfPages) vs \(b.numberOfPages)"); exit(1)
}

var ok = true
for n in 1...a.numberOfPages {
    guard let pa = a.page(at: n), let pb = b.page(at: n),
          let ra = render(pa), let rb = render(pb) else {
        print("page \(n): RENDER_FAILED"); ok = false; continue
    }
    guard ra.w == rb.w, ra.h == rb.h else {
        print("page \(n): SIZE_MISMATCH \(ra.w)x\(ra.h) vs \(rb.w)x\(rb.h)"); ok = false; continue
    }
    var total = 0.0
    var worst = 0.0
    for by in stride(from: 0, to: ra.h, by: block) {
        for bx in stride(from: 0, to: ra.w, by: block) {
            var sum = 0.0, count = 0.0
            for y in by..<min(by + block, ra.h) {
                for x in bx..<min(bx + block, ra.w) {
                    let i = (y * ra.w + x) * 4
                    for c in 0..<3 { sum += Double(abs(Int(ra.pixels[i + c]) - Int(rb.pixels[i + c]))) }
                    count += 3
                }
            }
            total += sum
            worst = max(worst, sum / count)
        }
    }
    let mean = total / Double(ra.w * ra.h * 3)
    let pass = mean <= maxMeanDiff && worst <= maxBlockDiff
    if !pass { ok = false }
    print(String(format: "page %d: mean %.2f, worst block %.1f %@", n, mean, worst, pass ? "ok" : "MISMATCH"))
}
print(ok ? "PARITY_OK" : "PARITY_FAILED")
exit(ok ? 0 : 1)
