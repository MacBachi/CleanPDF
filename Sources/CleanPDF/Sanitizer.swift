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
import CoreText
import ImageIO
import Vision
import UniformTypeIdentifiers

/// Options controlling the sanitization process.
struct SanitizeOptions: Sendable {
    /// Render resolution in dots per inch. 200 is a good balance of
    /// readability and file size; 300 for fine print.
    var dpi: CGFloat = 200
    /// JPEG quality (0...1) for the page images embedded in the output.
    var jpegQuality: CGFloat = 0.85
    /// Run on-device OCR and embed an invisible (drawn, non-interactive)
    /// text layer so the sanitized PDF stays searchable.
    var ocr: Bool = true
    /// Preferred OCR languages.
    var ocrLanguages: [String] = ["de-DE", "en-US"]
}

/// Upper bounds on the bitmap rendered for a single page. A PDF can declare a
/// page of up to 14400 x 14400 pt in a few hundred bytes; rendered at 200 dpi
/// that is a 1.6-gigapixel bitmap (~6.4 GB). Pages above the budget are
/// rendered at a reduced resolution instead; their size in points is kept.
enum RenderBudget {
    /// 50 MP ≈ 200 MB of RGBA. DIN A2 at 300 dpi (35 MP) still fits.
    static let maxPixels: Double = 50_000_000
    /// Longest bitmap side; keeps well inside JPEG and CoreGraphics limits.
    static let maxSide: Double = 20_000

    /// Pixels per point for a page of `pointSize` at the requested dpi,
    /// reduced as needed to stay within the budget. Nil for degenerate sizes.
    static func scale(for pointSize: CGSize, dpi: CGFloat) -> CGFloat? {
        let w = Double(pointSize.width), h = Double(pointSize.height)
        guard w.isFinite, h.isFinite, w > 0, h > 0, dpi > 0 else { return nil }
        let requested = Double(dpi) / 72.0
        let byArea = (maxPixels / (w * h)).squareRoot()
        let bySide = maxSide / max(w, h)
        return CGFloat(min(requested, byArea, bySide))
    }
}

/// What a sanitize run reports back besides the output file.
struct SanitizeResult: Sendable {
    var pageCount: Int
    /// 1-based numbers of pages rendered below the requested dpi because
    /// they exceeded the render budget.
    var downscaledPages: [Int] = []
}

enum SanitizeError: LocalizedError {
    case cannotCreateOutput
    case encodingFailed(page: Int)

    var errorDescription: String? {
        switch self {
        case .cannotCreateOutput: return "Ausgabedatei konnte nicht erstellt werden."
        case .encodingFailed(let page): return "Seite \(page) konnte nicht kodiert werden."
        }
    }
}

/// Rebuilds a PDF from scratch out of rendered page pixels.
///
/// Security model: the untrusted PDF is parsed and rendered only inside the
/// sandboxed worker (see Worker.swift and IsolatedPDF.swift), which can send
/// back nothing but page sizes and raw pixels. This side builds a brand-new
/// PDF from those pixels with CoreGraphics: page-sized JPEG images plus,
/// optionally, invisible drawn text from local OCR. Nothing from the source
/// file's object structure reaches the output — no JavaScript, no actions,
/// no annotations or links, no attachments, no forms, no signatures, no
/// metadata, no external references.
enum Sanitizer {

    /// Sanitize `input` into `output`. Reports progress as (currentPage, pageCount).
    static func sanitize(
        input: URL,
        output: URL,
        options: SanitizeOptions = SanitizeOptions(),
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> SanitizeResult {
        var result = SanitizeResult(pageCount: 0)
        var pdfContext: CGContext?

        do {
            try IsolatedPDF.render(input: input, dpi: options.dpi, onPageCount: { count in
                result.pageCount = count
                progress?(1, count)
            }, onPage: { frame in
                var pageBox = CGRect(origin: .zero, size: frame.pointSize)
                if pdfContext == nil {
                    // Deliberately minimal document info: nothing from the source.
                    let info: [CFString: Any] = [kCGPDFContextCreator: "CleanPDF"]
                    pdfContext = CGContext(output as CFURL, mediaBox: &pageBox, info as CFDictionary)
                }
                guard let context = pdfContext else { throw SanitizeError.cannotCreateOutput }
                guard let jpeg = jpegBackedImage(from: frame.image, quality: options.jpegQuality) else {
                    throw SanitizeError.encodingFailed(page: frame.pageNumber)
                }
                if frame.downscaled {
                    result.downscaledPages.append(frame.pageNumber)
                }

                let boxData = Data(bytes: &pageBox, count: MemoryLayout<CGRect>.size)
                context.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
                context.draw(jpeg, in: pageBox)
                if options.ocr {
                    drawInvisibleTextLayer(from: frame.image, into: context,
                                           pageBox: pageBox, languages: options.ocrLanguages)
                }
                context.endPDFPage()
                if frame.pageNumber < result.pageCount {
                    progress?(frame.pageNumber + 1, result.pageCount)
                }
            })
        } catch {
            pdfContext?.closePDF()
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        pdfContext?.closePDF()
        return result
    }

    /// Re-encode as JPEG and wrap the JPEG data in a CGImage so the PDF
    /// context stores compact DCT-encoded data instead of a raw bitmap.
    private static func jpegBackedImage(from image: CGImage, quality: CGFloat) -> CGImage? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let provider = CGDataProvider(data: data as CFData)
        else { return nil }
        return CGImage(
            jpegDataProviderSource: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    /// Runs Vision OCR on the rendered page image and draws the recognized
    /// text invisibly (CGTextDrawingMode.invisible) at the matching positions,
    /// so text search and selection keep working. This is plain drawn text —
    /// it carries no actions, links, or interactivity.
    private static func drawInvisibleTextLayer(
        from image: CGImage,
        into context: CGContext,
        pageBox: CGRect,
        languages: [String]
    ) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages

        let handler = VNImageRequestHandler(cgImage: image)
        guard (try? handler.perform([request])) != nil,
              let observations = request.results, !observations.isEmpty
        else { return }

        context.saveGState()
        context.setTextDrawingMode(.invisible)

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first,
                  !candidate.string.isEmpty else { continue }
            // Normalized rect, origin bottom-left — same convention as PDF space.
            let box = observation.boundingBox
            let rect = CGRect(
                x: pageBox.minX + box.minX * pageBox.width,
                y: pageBox.minY + box.minY * pageBox.height,
                width: box.width * pageBox.width,
                height: box.height * pageBox.height
            )
            guard rect.width > 0.5, rect.height > 0.5 else { continue }

            // Measure at the box height, then scale the font size uniformly so
            // the line width matches the box. Uniform scaling keeps glyph
            // advances proportional, so text extraction/search doesn't see
            // spurious gaps (which a horizontally stretched text matrix causes).
            func makeLine(fontSize: CGFloat) -> CTLine {
                let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
                let attributed = NSAttributedString(
                    string: candidate.string,
                    attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
                )
                return CTLineCreateWithAttributedString(attributed)
            }

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let probe = makeLine(fontSize: rect.height)
            let naturalWidth = CGFloat(CTLineGetTypographicBounds(probe, &ascent, &descent, nil))
            guard naturalWidth > 0 else { continue }

            let fittedSize = rect.height * (rect.width / naturalWidth)
            let line = makeLine(fontSize: fittedSize)
            var fittedDescent: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, nil, &fittedDescent, nil)
            context.textMatrix = CGAffineTransform(translationX: rect.minX, y: rect.minY + fittedDescent)
            context.textPosition = .zero
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }
}

/// Human-readable note for pages rendered below the requested resolution.
func downscaleNote(_ pages: [Int]) -> String {
    let list = pages.prefix(10).map(String.init).joined(separator: ", ")
        + (pages.count > 10 ? " …" : "")
    let noun = pages.count == 1 ? "Seite" : "Seiten"
    return "\(noun) \(list) wegen Übergröße mit reduzierter Auflösung gerendert"
}
