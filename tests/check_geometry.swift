// Regression guard for the "page rendered too small, centered on a blank
// page" bug. Renders the first page of two PDFs at identical size and compares
// the bounding box of the dark (content) pixels. Prints GEOMETRY_OK on match.
//
// Usage: swift tests/check_geometry.swift original.pdf sanitized.pdf
import CoreGraphics
import Foundation

func contentBox(_ path: String) -> (w: Int, h: Int, box: (Int, Int, Int, Int))? {
    guard let doc = CGPDFDocument(URL(fileURLWithPath: path) as CFURL),
          let page = doc.page(at: 1) else { return nil }
    let crop = page.getBoxRect(.cropBox)
    let rotated = abs(page.rotationAngle) % 180 == 90
    let w = Int(rotated ? crop.height : crop.width)
    let h = Int(rotated ? crop.width : crop.height)
    guard w > 0, h > 0,
          let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: w, height: h),
                                             rotate: 0, preserveAspectRatio: true))
    ctx.drawPDFPage(page)
    guard let data = ctx.data else { return nil }
    let ptr = data.assumingMemoryBound(to: UInt8.self)
    let bpr = ctx.bytesPerRow
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w where ptr[y * bpr + x * 4] < 200 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    return (w, h, (minX, minY, maxX, maxY))
}

let args = CommandLine.arguments
guard args.count >= 3, let a = contentBox(args[1]), let b = contentBox(args[2]) else {
    print("READ_FAILED"); exit(1)
}
// Same page size, and content bounding boxes within a few px (JPEG + OCR
// layer can nudge edges slightly).
let tol = 6
func close(_ x: Int, _ y: Int) -> Bool { abs(x - y) <= tol }
let sizeOK = a.w == b.w && a.h == b.h
let boxOK = close(a.box.0, b.box.0) && close(a.box.1, b.box.1)
    && close(a.box.2, b.box.2) && close(a.box.3, b.box.3)
if sizeOK && boxOK {
    print("GEOMETRY_OK")
} else {
    print("MISMATCH size \(a.w)x\(a.h) vs \(b.w)x\(b.h) box \(a.box) vs \(b.box)")
    exit(1)
}
