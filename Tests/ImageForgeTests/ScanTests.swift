//
//  ScanTests.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Photographed pages into flat ones, and flat ones into PDFs. The page is
//  synthetic — real text, warped by a known perspective — so the corners
//  Vision should find and the words a reader should get back are both
//  known before the test runs.
//

import CoreGraphics
import PDFKit
import Vision
import XCTest
@testable import ImageForge

final class ScanTests: XCTestCase {

    // MARK: - The maths

    func testAnUprightRectangleFlattensToItself() {
        let quad = Quadrilateral(topLeft: CGPoint(x: 10, y: 20), topRight: CGPoint(x: 410, y: 20),
                                 bottomRight: CGPoint(x: 410, y: 620), bottomLeft: CGPoint(x: 10, y: 620),
                                 confidence: 1)
        XCTAssertEqual(Geometry.flattenedSize(of: quad), CGSize(width: 400, height: 600))
    }

    func testForeshorteningIsUndoneWithTheNearerEdge() {
        // The far (top) edge is 300 long, the near (bottom) one 400: the
        // page is at least as wide as the edge foreshortening shrank least.
        let quad = Quadrilateral(topLeft: CGPoint(x: 50, y: 0), topRight: CGPoint(x: 350, y: 0),
                                 bottomRight: CGPoint(x: 400, y: 500), bottomLeft: CGPoint(x: 0, y: 500),
                                 confidence: 1)
        XCTAssertEqual(Geometry.flattenedSize(of: quad).width, 400)
    }

    func testForcingAShapeKeepsTheLongerSide() {
        let quad = Quadrilateral(topLeft: .zero, topRight: CGPoint(x: 1000, y: 0),
                                 bottomRight: CGPoint(x: 1000, y: 1300), bottomLeft: CGPoint(x: 0, y: 1300),
                                 confidence: 1)
        let size = Geometry.flattenedSize(of: quad, aspectRatio: PaperSize.a4.aspectRatio)
        XCTAssertEqual(size.height, 1300)
        XCTAssertEqual(size.width, (1300 / PaperSize.a4.aspectRatio).rounded())
    }

    func testPaperIsMatchedOnlyWhenClose() {
        XCTAssertEqual(PaperSize.nearest(to: CGSize(width: 1240, height: 1754)), .a4)
        XCTAssertEqual(PaperSize.nearest(to: CGSize(width: 1754, height: 1240)), .a4, "either way up")
        XCTAssertEqual(PaperSize.nearest(to: CGSize(width: 850, height: 1100)), .letter)
        XCTAssertNil(PaperSize.nearest(to: CGSize(width: 850, height: 1400)), "Legal is never guessed")
        // The two wrong answers real photographs got from a 4% tolerance.
        XCTAssertNil(PaperSize.nearest(to: CGSize(width: 1000, height: 1608)), "a hotel bill is not Legal")
        XCTAssertNil(PaperSize.nearest(to: CGSize(width: 1000, height: 1260)), "a sign is not Letter")
        XCTAssertNil(PaperSize.nearest(to: CGSize(width: 600, height: 2400)), "a receipt is no sheet")
        XCTAssertNil(PaperSize.nearest(to: CGSize(width: 1000, height: 1000)))
    }

    func testAPageSizeIsTheSheetOrTheResolution() {
        XCTAssertEqual(PDFWriter.pageSize(forPixels: CGSize(width: 2480, height: 3508), paper: .a4), PaperSize.a4.points)
        let landscape = PDFWriter.pageSize(forPixels: CGSize(width: 3300, height: 2550), paper: .letter)
        XCTAssertEqual(landscape, CGSize(width: 792, height: 612), "Letter, turned")
        // No sheet named: the picture's own size at 300 dpi, never a guess.
        let own = PDFWriter.pageSize(forPixels: CGSize(width: 2480, height: 3508))
        XCTAssertEqual(own.width, 595.2, accuracy: 0.001)
        XCTAssertEqual(own.height, 841.92, accuracy: 0.001)
        // A 600×2400 receipt at 300 dpi is 2 × 8 inches.
        XCTAssertEqual(PDFWriter.pageSize(forPixels: CGSize(width: 600, height: 2400)),
                       CGSize(width: 144, height: 576))
    }

    // MARK: - Resolving

    func testNoPageMeansTheFrameIsKept() throws {
        let image = TestImages.solid(.white, width: 40, height: 60)
        XCTAssertEqual(try Pipeline.resolve([.findPage(.automatic)], for: image), [])
    }

    func testAnUnsurePageIsNotTrusted() throws {
        let image = TestImages.solid(.white, width: 40, height: 60)
        let weak = Quadrilateral(topLeft: .zero, topRight: CGPoint(x: 40, y: 0),
                                 bottomRight: CGPoint(x: 40, y: 60), bottomLeft: CGPoint(x: 0, y: 60),
                                 confidence: 0.2)
        XCTAssertEqual(try Pipeline.resolve([.findPage(.automatic)], for: image, document: weak), [])
    }

    func testAFoundPageBecomesAPerspective() throws {
        let image = TestImages.solid(.white, width: 400, height: 600)
        let quad = Quadrilateral(topLeft: CGPoint(x: 10, y: 10), topRight: CGPoint(x: 390, y: 10),
                                 bottomRight: CGPoint(x: 390, y: 590), bottomLeft: CGPoint(x: 10, y: 590),
                                 confidence: 0.9)
        let resolved = try Pipeline.resolve([.findPage(PageSpec(snapsToPaper: false))],
                                            for: image, document: quad)
        XCTAssertEqual(resolved, [.perspective(quad, aspectRatio: nil)])
    }

    func testNewOperationsSurviveARecipe() throws {
        let quad = Quadrilateral(topLeft: .zero, topRight: CGPoint(x: 1, y: 0),
                                 bottomRight: CGPoint(x: 1, y: 1), bottomLeft: CGPoint(x: 0, y: 1),
                                 confidence: 0.5)
        let steps: [ImageOperation] = [.findPage(PageSpec(paper: .letter)),
                                       .perspective(quad, aspectRatio: 1.5),
                                       .cleanDocument(.blackAndWhite)]
        let decoded = try JSONDecoder().decode([ImageOperation].self, from: JSONEncoder().encode(steps))
        XCTAssertEqual(decoded, steps)
    }

    // MARK: - The pixels

    func testTheCornersAreFoundWithinAFewPixels() async throws {
        let photo = TestImages.photographedPage()
        let detected = try await Detectors.document(in: photo.image)
        let found = try XCTUnwrap(detected)
        for (got, want) in zip(found.corners, photo.corners.corners) {
            // 2400 px frame; 1% of it is 24 px.
            XCTAssertLessThan(Geometry.distance(got, want), 24, "\(got) vs \(want)")
        }
    }

    func testAPhotographedPageComesBackFlatAndA4() async throws {
        let directory = TestImages.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("photo.png")
        try ImageEncoder.write(try ImageEncoder.encode(TestImages.photographedPage().image, format: .png,
                                                       spec: EncodeSpec(format: .png)),
                               to: url, overwrites: true)

        let measured = try await ImageForge.scan(url)
        XCTAssertNil(measured.paper, "no sheet is guessed by default")
        let page = try await ImageForge.scan(url, page: .snapping)
        XCTAssertTrue(page.foundPage)
        XCTAssertEqual(page.paper, .a4)
        let ratio = Double(page.image.height) / Double(page.image.width)
        XCTAssertEqual(ratio, PaperSize.a4.aspectRatio, accuracy: 0.01)

        // The point of flattening: every line reads back.
        let read = try await RecognizeTextRequest().perform(on: page.image)
            .compactMap { $0.topCandidates(1).first?.string }
        XCTAssertEqual(read, TestImages.pageLines)
    }

    func testGivenCornersSkipDetection() async throws {
        let directory = TestImages.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("blank.png")
        try ImageEncoder.write(try ImageEncoder.encode(TestImages.solid(.white, width: 300, height: 300),
                                                       format: .png, spec: EncodeSpec(format: .png)),
                               to: url, overwrites: true)
        let corners = Quadrilateral(topLeft: CGPoint(x: 50, y: 50), topRight: CGPoint(x: 250, y: 50),
                                    bottomRight: CGPoint(x: 250, y: 250), bottomLeft: CGPoint(x: 50, y: 250),
                                    confidence: 1)
        let page = try await ImageForge.scan(url, page: PageSpec(snapsToPaper: false),
                                             corners: corners, tone: nil)
        XCTAssertEqual(page.image.pixelSize, CGSize(width: 200, height: 200))
        XCTAssertEqual(page.operations, [.perspective(corners, aspectRatio: nil)])
    }

    func testGreyAndBlackAndWhiteAreOneChannel() throws {
        let image = TestImages.pageOnDesk()
        for tone in [DocumentTone.gray, .blackAndWhite] {
            let cleaned = try Renderer.cleanDocument(image, tone: tone)
            XCTAssertEqual(cleaned.colorSpace?.model, .monochrome, "\(tone)")
            XCTAssertEqual(cleaned.pixelSize, image.pixelSize)
        }
        let color = try Renderer.cleanDocument(image, tone: .color)
        XCTAssertEqual(color.colorSpace?.model, .rgb)
        XCTAssertFalse(color.hasAlphaChannel, "an opaque photo stays opaque")
    }

    func testAFlattenedPageIsOpaque() throws {
        let photo = TestImages.photographedPage()
        let flat = try Renderer.perspective(photo.image, photo.corners,
                                            size: Geometry.flattenedSize(of: photo.corners))
        XCTAssertFalse(flat.hasAlphaChannel)
    }

    func testBlackAndWhiteIsInkOrPaper() throws {
        let cleaned = try Renderer.cleanDocument(TestImages.pageOnDesk(), tone: .blackAndWhite)
        let gray = try Renderer.convert(cleaned, to: .sRGB)
        for row in TestImages.read(gray).enumerated() where row.offset % 97 == 0 {
            for pixel in row.element.enumerated() where pixel.offset % 89 == 0 {
                XCTAssertTrue(pixel.element.r < 8 || pixel.element.r > 247, "\(pixel.element)")
            }
        }
    }

    // MARK: - PDF

    func testTheTextLayerReadsBackAndIsFoundWhereItSits() throws {
        let page = PDFImagePage(image: TestImages.pageOnDesk(), size: PaperSize.a4.points,
                                text: [PDFTextRun(text: "Northwind Trading",
                                                  frame: CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.03))])
        let document = try XCTUnwrap(PDFDocument(data: try PDFWriter.data(for: [page, page])))
        XCTAssertEqual(document.pageCount, 2)
        let pdfPage = try XCTUnwrap(document.page(at: 0))
        XCTAssertEqual(pdfPage.string?.trimmingCharacters(in: .whitespacesAndNewlines), "Northwind Trading")
        XCTAssertEqual(pdfPage.bounds(for: .mediaBox).size, PaperSize.a4.points)

        let hit = try XCTUnwrap(document.findString("Trading", withOptions: []).first)
        let bounds = hit.bounds(for: pdfPage)
        XCTAssertEqual(bounds.midY, 0.815 * PaperSize.a4.points.height, accuracy: 12)
    }

    func testJPEGPagesAreSmallerThanLosslessOnes() throws {
        let image = TestImages.photographedPage().image
        let size = PDFWriter.pageSize(forPixels: image.pixelSize)
        let jpeg = try PDFWriter.data(for: [PDFImagePage(image: image, size: size)])
        let lossless = try PDFWriter.data(for: [PDFImagePage(image: image, size: size, jpegQuality: nil)])
        XCTAssertLessThan(jpeg.count, lossless.count)
    }

    func testFinePicturesAreCappedAtTheResolution() throws {
        // 2400 px across an A4 page is 290 dpi; capped at 150 it halves.
        let image = TestImages.photographedPage().image
        let page = PDFImagePage(image: image, size: PaperSize.a4.points)
        let capped = try PDFWriter.embeddable(page, maximumDPI: 150)
        XCTAssertLessThanOrEqual(CGFloat(capped.width), PaperSize.a4.points.width / 72 * 150 + 1)
    }
}
