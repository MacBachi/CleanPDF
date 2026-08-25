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

enum SanitizeError: LocalizedError {
    case cannotOpen
    case encrypted
    case noPages
    case cannotCreateOutput
    case renderFailed(page: Int)

    var errorDescription: String? {
        switch self {
        case .cannotOpen: return "Datei konnte nicht als PDF geöffnet werden."
        case .encrypted: return "PDF ist passwortgeschützt. Bitte zuerst entsperren (z. B. in Vorschau exportieren)."
        case .noPages: return "PDF enthält keine Seiten."
        case .cannotCreateOutput: return "Ausgabedatei konnte nicht erstellt werden."
        case .renderFailed(let page): return "Seite \(page) konnte nicht gerendert werden."
        }
    }
}

/// Rebuilds a PDF from scratch by rasterizing every page.
///
/// Security model: the output PDF is constructed fresh by CoreGraphics and
/// contains ONLY page-sized images (plus, optionally, invisible drawn text
/// from local OCR). Nothing from the source file's object structure is
/// copied over — no JavaScript, no actions (OpenAction/AA/Launch), no
/// annotations or links, no embedded/attached files, no forms (AcroForm/XFA),
/// no digital signatures or certificates, no metadata, no external references.
/// Rendering itself uses CGPDFDocument, a pure rasterizer that executes no
/// scripts and performs no network access.
enum Sanitizer {

    /// Sanitize `input` into `output`. Reports progress as (currentPage, pageCount).
    static func sanitize(
        input: URL,
        output: URL,
        options: SanitizeOptions = SanitizeOptions(),
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws {
        guard let doc = CGPDFDocument(input as CFURL) else {
            throw SanitizeError.cannotOpen
        }
        if doc.isEncrypted && !doc.unlockWithPassword("") {
            throw SanitizeError.encrypted
        }
        let pageCount = doc.numberOfPages
        guard pageCount > 0, let firstPage = doc.page(at: 1) else {
            throw SanitizeError.noPages
        }

        var defaultBox = pageBoxSize(of: firstPage)
        // Deliberately minimal document info: nothing is carried over from the source.
        let pdfInfo: [CFString: Any] = [kCGPDFContextCreator: "CleanPDF"]
        guard let pdfContext = CGContext(output as CFURL, mediaBox: &defaultBox, pdfInfo as CFDictionary) else {
            throw SanitizeError.cannotCreateOutput
        }

        for pageNumber in 1...pageCount {
            progress?(pageNumber, pageCount)
            guard let page = doc.page(at: pageNumber) else { continue }

            let pageBox = pageBoxSize(of: page)
            guard let rendered = renderPage(page, pointSize: pageBox.size, options: options) else {
                pdfContext.closePDF()
                try? FileManager.default.removeItem(at: output)
                throw SanitizeError.renderFailed(page: pageNumber)
            }

            var mediaBox = pageBox
            let boxData = Data(bytes: &mediaBox, count: MemoryLayout<CGRect>.size)
            let pageInfo: [CFString: Any] = [kCGPDFContextMediaBox: boxData]
            pdfContext.beginPDFPage(pageInfo as CFDictionary)
            pdfContext.draw(rendered.image, in: pageBox)
            if options.ocr {
                drawInvisibleTextLayer(
                    from: rendered.image,
                    into: pdfContext,
                    pageBox: pageBox,
                    languages: options.ocrLanguages
                )
            }
            pdfContext.endPDFPage()
        }
        pdfContext.closePDF()
    }

    /// Effective page rectangle in points, normalized to origin zero and
    /// accounting for the page's /Rotate entry.
    private static func pageBoxSize(of page: CGPDFPage) -> CGRect {
        let crop = page.getBoxRect(.cropBox)
        let rotated = abs(page.rotationAngle) % 180 == 90
        let width = rotated ? crop.height : crop.width
        let height = rotated ? crop.width : crop.height
        return CGRect(x: 0, y: 0, width: width, height: height)
    }

    private struct RenderedPage {
        /// JPEG-backed CGImage; Quartz embeds the JPEG data directly (DCTDecode).
        var image: CGImage
    }

    private static func renderPage(_ page: CGPDFPage, pointSize: CGSize, options: SanitizeOptions) -> RenderedPage? {
        let scale = options.dpi / 72.0
        let pixelWidth = max(1, Int((pointSize.width * scale).rounded()))
        let pixelHeight = max(1, Int((pointSize.height * scale).rounded()))

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmap = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        let pixelRect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        bitmap.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        bitmap.fill(pixelRect)
        bitmap.interpolationQuality = .high
        bitmap.saveGState()
        // getDrawingTransform never scales UP, so it must not be handed the
        // (larger) pixel rect — that would draw the page 1:1, centered on a
        // mostly blank bitmap. Apply the dpi scale ourselves, then let the
        // transform handle only rotation and crop-box origin at 1:1 point size.
        bitmap.scaleBy(x: scale, y: scale)
        let pointRect = CGRect(x: 0, y: 0, width: pointSize.width, height: pointSize.height)
        bitmap.concatenate(page.getDrawingTransform(.cropBox, rect: pointRect, rotate: 0, preserveAspectRatio: true))
        bitmap.drawPDFPage(page)
        bitmap.restoreGState()

        guard let raw = bitmap.makeImage(),
              let jpegBacked = jpegBackedImage(from: raw, quality: options.jpegQuality)
        else { return nil }
        return RenderedPage(image: jpegBacked)
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