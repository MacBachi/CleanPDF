// CleanPDF — turn untrusted PDFs into guaranteed-passive, safe PDFs.
// Copyright (C) 2026 CleanPDF contributors
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. This program is distributed WITHOUT ANY WARRANTY; see
// the GNU General Public License <https://www.gnu.org/licenses/> for details.

// Draws the CleanPDF app icon (1024x1024 PNG).
// Recreation of the provided icon artwork: blue background, green ring with
// sparkles, document with "P" and text lines, red/white medical-style plus.
// Run: swift assets/generate_icon.swift assets/AppIcon.png
import CoreGraphics
import CoreText
import ImageIO
import Foundation
import UniformTypeIdentifiers

let size: CGFloat = 1024
let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1
    )
}

let blueTop = rgb(0x4F9CF7)
let blueBottom = rgb(0x2B62E8)
let green = rgb(0x77C24F)
let docBlue = rgb(0x2D66D9)
let docFill = rgb(0xF2F7FF)
let plusRed = rgb(0xE8503A)
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

// Flip to top-left origin for layout sanity.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// --- Background: rounded square with vertical gradient -------------------
let bgPath = CGPath(
    roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
    cornerWidth: 230, cornerHeight: 230, transform: nil
)
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [blueTop, blueBottom] as CFArray, locations: [0, 1]
)!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 200, y: 0), end: CGPoint(x: 824, y: size), options: [])
ctx.restoreGState()

// --- Green ring + white disc ---------------------------------------------
let center = CGPoint(x: 512, y: 512)
ctx.setFillColor(white)
ctx.fillEllipse(in: CGRect(x: center.x - 392, y: center.y - 392, width: 784, height: 784))
ctx.setStrokeColor(green)
ctx.setLineWidth(48)
ctx.setLineCap(.round)
// Ring with a gap at the top-right, where the big sparkle sits.
// (Coordinate system is flipped, so "clockwise: false" runs the LONG way
// from the gap's end around the circle back to its start.)
ctx.addArc(center: center, radius: 428, startAngle: -.pi * 0.13, endAngle: -.pi * 0.37, clockwise: false)
ctx.strokePath()

// --- Sparkles -------------------------------------------------------------
func sparkle(at p: CGPoint, radius s: CGFloat) {
    ctx.beginPath()
    ctx.move(to: CGPoint(x: p.x, y: p.y - s))
    ctx.addQuadCurve(to: CGPoint(x: p.x + s, y: p.y), control: p)
    ctx.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s), control: p)
    ctx.addQuadCurve(to: CGPoint(x: p.x - s, y: p.y), control: p)
    ctx.addQuadCurve(to: CGPoint(x: p.x, y: p.y - s), control: p)
    ctx.closePath()
    ctx.setFillColor(green)
    ctx.fillPath()
}
sparkle(at: CGPoint(x: 858, y: 148), radius: 78)
sparkle(at: CGPoint(x: 948, y: 268), radius: 36)
ctx.setFillColor(green)
ctx.fillEllipse(in: CGRect(x: 774, y: 262, width: 26, height: 26))
sparkle(at: CGPoint(x: 152, y: 868), radius: 68)
sparkle(at: CGPoint(x: 80, y: 748), radius: 34)
ctx.fillEllipse(in: CGRect(x: 232, y: 758, width: 24, height: 24))

// --- Document -------------------------------------------------------------
let doc = CGRect(x: 330, y: 235, width: 330, height: 470)
let docPath = CGPath(roundedRect: doc, cornerWidth: 46, cornerHeight: 46, transform: nil)
ctx.addPath(docPath)
ctx.setFillColor(docFill)
ctx.fillPath()
ctx.addPath(docPath)
ctx.setStrokeColor(docBlue)
ctx.setLineWidth(34)
ctx.strokePath()

// "P" (drawn un-flipped so the glyph isn't mirrored)
let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 170, nil)
let attr = NSAttributedString(
    string: "P",
    attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): docBlue,
    ]
)
let line = CTLineCreateWithAttributedString(attr)
ctx.saveGState()
ctx.translateBy(x: 392, y: 430)
ctx.scaleBy(x: 1, y: -1)
ctx.textPosition = .zero
CTLineDraw(line, ctx)
ctx.restoreGState()

// Text lines
ctx.setFillColor(docBlue)
let lineX: CGFloat = 392
let lineWidths: [CGFloat] = [210, 210, 150]
var lineY: CGFloat = 486
for width in lineWidths {
    ctx.addPath(CGPath(
        roundedRect: CGRect(x: lineX, y: lineY, width: width, height: 34),
        cornerWidth: 17, cornerHeight: 17, transform: nil
    ))
    ctx.fillPath()
    lineY += 72
}

// --- Plus ------------------------------------------------------------------
func plusPath(center p: CGPoint, halfArm a: CGFloat, halfThickness t: CGFloat, corner r: CGFloat) -> CGPath {
    let pts: [CGPoint] = [
        CGPoint(x: p.x - t, y: p.y - a), CGPoint(x: p.x + t, y: p.y - a),
        CGPoint(x: p.x + t, y: p.y - t), CGPoint(x: p.x + a, y: p.y - t),
        CGPoint(x: p.x + a, y: p.y + t), CGPoint(x: p.x + t, y: p.y + t),
        CGPoint(x: p.x + t, y: p.y + a), CGPoint(x: p.x - t, y: p.y + a),
        CGPoint(x: p.x - t, y: p.y + t), CGPoint(x: p.x - a, y: p.y + t),
        CGPoint(x: p.x - a, y: p.y - t), CGPoint(x: p.x - t, y: p.y - t),
    ]
    let path = CGMutablePath()
    path.move(to: CGPoint(x: (pts[0].x + pts[11].x) / 2, y: pts[0].y))
    for i in 0..<pts.count {
        let current = pts[i]
        let next = pts[(i + 1) % pts.count]
        path.addArc(tangent1End: current, tangent2End: next, radius: r)
    }
    path.closeSubpath()
    return path
}

let plus = plusPath(center: CGPoint(x: 668, y: 668), halfArm: 168, halfThickness: 58, corner: 24)
// White halo separates the plus from the document underneath.
ctx.addPath(plus)
ctx.setStrokeColor(white)
ctx.setLineWidth(88)
ctx.setLineJoin(.round)
ctx.strokePath()
ctx.addPath(plus)
ctx.setFillColor(white)
ctx.fillPath()
ctx.addPath(plus)
ctx.setStrokeColor(plusRed)
ctx.setLineWidth(34)
ctx.strokePath()

// --- Write PNG -------------------------------------------------------------
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil
)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(outPath)")