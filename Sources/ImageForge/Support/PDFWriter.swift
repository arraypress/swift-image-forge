//
//  PDFWriter.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Pictures into a PDF, one per page, with an optional invisible text layer
//  — what a scanner app hands back. Two details decide whether the file is
//  any good:
//
//  - The picture goes in as JPEG bytes, not pixels. Core Graphics passes a
//    JPEG-backed image straight into the PDF as DCT data; handed raw pixels
//    it Flate-compresses them, and a photographed page comes out several
//    times larger.
//  - The text is drawn in invisible render mode, stretched to the width of
//    the line it was read from, so a search highlights the word where the
//    eye sees it. Probed: PDFKit reads the text back verbatim and a search
//    lands on the right line.
//

import CoreGraphics
import CoreText
import Foundation

/// Writes image pages, with or without a text layer, as a PDF.
public enum PDFWriter {

    /// The resolution assumed for a page that matches no standard sheet.
    ///
    /// A flattened phone photo of a receipt has no paper size to borrow, so
    /// its pixels are given a physical size at a scanner's resolution.
    public static let defaultDPI: Double = 300

    /// The size a page should be, in points.
    ///
    /// - Parameters:
    ///   - pixels: The picture's size in pixels.
    ///   - paper: A sheet to use, or nil to try the nearest standard one and
    ///     fall back to `dpi`.
    ///   - dpi: The resolution to assume when no sheet fits.
    /// - Returns: The page size, turned to match the picture.
    public static func pageSize(forPixels pixels: CGSize, paper: PaperSize? = nil,
                                dpi: Double = defaultDPI) -> CGSize {
        guard pixels.width > 0, pixels.height > 0 else { return PaperSize.a4.points }
        if let sheet = paper ?? PaperSize.nearest(to: pixels) {
            let points = sheet.points
            return pixels.width > pixels.height
                ? CGSize(width: points.height, height: points.width)
                : points
        }
        let scale = 72 / CGFloat(dpi)
        return CGSize(width: pixels.width * scale, height: pixels.height * scale)
    }

    /// The PDF bytes for a list of pages.
    ///
    /// - Parameters:
    ///   - pages: The pages, in order.
    ///   - maximumDPI: Downscale any picture finer than this on its page.
    ///     A 12-megapixel photo on an A4 page is 400 dpi; nobody reads it
    ///     at more than 300, and the difference is a third of the file.
    /// - Returns: The document.
    /// - Throws: ``ImageForgeError/emptyResult(_:)`` when there are no
    ///   pages or a page cannot be drawn.
    public static func data(for pages: [PDFImagePage], maximumDPI: Double = defaultDPI) throws -> Data {
        guard !pages.isEmpty else { throw ImageForgeError.emptyResult("a PDF with no pages") }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw ImageForgeError.emptyResult("a PDF context")
        }
        for page in pages {
            var box = CGRect(origin: .zero, size: page.size)
            let info = [kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size)]
            context.beginPDFPage(info as CFDictionary)
            context.draw(try embeddable(page, maximumDPI: maximumDPI), in: box)
            drawText(page.text, in: box, on: context)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    // MARK: - Pieces

    /// The picture as it should go into the file: no finer than the
    /// resolution cap, and JPEG-backed unless the page asked for lossless.
    static func embeddable(_ page: PDFImagePage, maximumDPI: Double) throws -> CGImage {
        var image = page.image
        let ceiling = CGSize(width: page.size.width / 72 * CGFloat(maximumDPI),
                             height: page.size.height / 72 * CGFloat(maximumDPI))
        if CGFloat(image.width) > ceiling.width * 1.05 || CGFloat(image.height) > ceiling.height * 1.05 {
            let factor = min(ceiling.width / CGFloat(image.width), ceiling.height / CGFloat(image.height))
            image = try Renderer.scale(image, to: CGSize(width: CGFloat(image.width) * factor,
                                                         height: CGFloat(image.height) * factor))
        }
        guard let quality = page.jpegQuality else { return image }

        let jpeg = try ImageEncoder.encode(image, format: .jpeg,
                                           spec: EncodeSpec(format: .jpeg, quality: quality, metadata: .strip))
        guard let provider = CGDataProvider(data: jpeg as CFData),
              let backed = CGImage(jpegDataProviderSource: provider, decode: nil,
                                   shouldInterpolate: true, intent: .defaultIntent) else {
            return image
        }
        return backed
    }

    /// Lays text invisibly over a page, each run stretched to its box.
    ///
    /// The font size is taken from the box's height and the run is then
    /// squeezed or stretched horizontally to the box's width, so the
    /// selection a search draws matches the line in the picture whatever
    /// typeface the page was printed in.
    static func drawText(_ runs: [PDFTextRun], in box: CGRect, on context: CGContext) {
        guard !runs.isEmpty else { return }
        context.saveGState()
        context.setTextDrawingMode(.invisible)
        for run in runs where !run.text.isEmpty {
            let rect = CGRect(x: run.frame.minX * box.width, y: run.frame.minY * box.height,
                              width: run.frame.width * box.width, height: run.frame.height * box.height)
            guard rect.width > 0, rect.height > 0 else { continue }
            let font = CTFontCreateWithName("Helvetica" as CFString, rect.height * 0.9, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: run.text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            guard width > 0 else { continue }
            context.saveGState()
            // Sit the baseline where a line of that height keeps its descenders.
            context.translateBy(x: rect.minX, y: rect.minY + rect.height * 0.15)
            context.scaleBy(x: rect.width / CGFloat(width), y: 1)
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
        }
        context.restoreGState()
    }
}
