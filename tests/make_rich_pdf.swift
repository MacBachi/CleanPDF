// Builds a feature-rich, benign PDF with CoreGraphics, the way ordinary apps
// write PDFs. Render-parity fixture: every feature here exercises a decoder
// or font engine inside the sandboxed worker, so a sandbox rule that breaks
// one of them shows up as a visual difference.
//
//   page 1: embedded TrueType (Andale Mono), CFF/OpenType (Helvetica Neue),
//           CJK (Hiragino/PingFang), emoji (Apple Color Emoji)
//   page 2: JPEG image (kept as DCTDecode), Display-P3 image (ICC-based),
//           axial + radial gradients (shadings), alpha blending (soft masks)
//
// Usage: swift tests/make_rich_pdf.swift out.pdf
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: CommandLine.arguments[1])
var media = CGRect(x: 0, y: 0, width: 612, height: 792)
let pdf = CGContext(out as CFURL, mediaBox: &media, nil)!

func text(_ s: String, font: String, size: CGFloat, at p: CGPoint, color: CGColor = CGColor(gray: 0, alpha: 1)) {
    let f = CTFontCreateWithName(font as CFString, size, nil)
    let attr = NSAttributedString(string: s, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): f,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ])
    pdf.textPosition = p
    CTLineDraw(CTLineCreateWithAttributedString(attr), pdf)
}

// A deterministic photo-like test image.
func testImage(width: Int, height: Int, space: CGColorSpace) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let g = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1), CGColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: width, y: height), options: [])
    for i in 0..<12 {
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: CGFloat(i) / 12, alpha: 0.8))
        ctx.fillEllipse(in: CGRect(x: 10 + i * width / 13, y: (i * 37) % (height - 40), width: 30, height: 30))
    }
    return ctx.makeImage()!
}

// --- Page 1: fonts ----------------------------------------------------------
pdf.beginPDFPage(nil)
text("Andale Mono (TrueType): The quick brown fox 0123456789", font: "AndaleMono", size: 16, at: CGPoint(x: 50, y: 720))
text("Helvetica Neue (OpenType/CFF): Sphinx of black quartz", font: "HelveticaNeue", size: 18, at: CGPoint(x: 50, y: 680))
text("Hiragino: 日本語のテキスト · PingFang: 中文文本", font: "HiraginoSans-W3", size: 18, at: CGPoint(x: 50, y: 640))
text("PingFang SC 简体中文 渲染测试", font: "PingFangSC-Regular", size: 18, at: CGPoint(x: 50, y: 600))
text("Emoji: 🛡️ 📄 ✅ 🔒", font: "AppleColorEmoji", size: 28, at: CGPoint(x: 50, y: 540))
text("Farbiger Text in Rot und Blau", font: "HelveticaNeue-Bold", size: 22, at: CGPoint(x: 50, y: 490),
     color: CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))
pdf.endPDFPage()

// --- Page 2: images, ICC, shadings, transparency ------------------------
pdf.beginPDFPage(nil)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
// JPEG-backed image: the PDF writer keeps it as DCTDecode.
let jpegData = NSMutableData()
let dest = CGImageDestinationCreateWithData(jpegData, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, testImage(width: 400, height: 260, space: srgb), [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
CGImageDestinationFinalize(dest)
let jpeg = CGImage(jpegDataProviderSource: CGDataProvider(data: jpegData as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
pdf.draw(jpeg, in: CGRect(x: 50, y: 500, width: 250, height: 162))
// Display P3 image: written with an ICCBased colour space.
let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
pdf.draw(testImage(width: 300, height: 200, space: p3), in: CGRect(x: 320, y: 500, width: 240, height: 160))
// Shadings.
let shade = CGGradient(colorsSpace: srgb, colors: [
    CGColor(red: 0, green: 0.6, blue: 0.3, alpha: 1), CGColor(red: 1, green: 0.85, blue: 0, alpha: 1),
] as CFArray, locations: [0, 1])!
pdf.saveGState()
pdf.clip(to: CGRect(x: 50, y: 300, width: 250, height: 160))
pdf.drawLinearGradient(shade, start: CGPoint(x: 50, y: 300), end: CGPoint(x: 300, y: 460), options: [])
pdf.restoreGState()
pdf.drawRadialGradient(shade, startCenter: CGPoint(x: 440, y: 380), startRadius: 5,
                       endCenter: CGPoint(x: 440, y: 380), endRadius: 80, options: [])
// Transparency: overlapping translucent shapes and an alpha-gradient image.
for (i, c) in [(0.9, 0.1, 0.1), (0.1, 0.7, 0.2), (0.1, 0.2, 0.9)].enumerated() {
    pdf.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 0.5))
    pdf.fillEllipse(in: CGRect(x: 80 + i * 60, y: 90, width: 150, height: 150))
}
let alphaCtx = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                         space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
alphaCtx.drawRadialGradient(CGGradient(colorsSpace: srgb, colors: [
    CGColor(red: 0.5, green: 0, blue: 0.8, alpha: 1), CGColor(red: 0.5, green: 0, blue: 0.8, alpha: 0),
] as CFArray, locations: [0, 1])!, startCenter: CGPoint(x: 100, y: 100), startRadius: 0,
    endCenter: CGPoint(x: 100, y: 100), endRadius: 100, options: [])
pdf.draw(alphaCtx.makeImage()!, in: CGRect(x: 360, y: 80, width: 180, height: 180))
pdf.endPDFPage()
pdf.closePDF()
print("wrote \(out.path)")
