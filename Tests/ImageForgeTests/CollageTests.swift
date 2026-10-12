//
//  CollageTests.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  The layout arithmetic against its promises — rows that run exactly edge
//  to edge, gaps that are exactly the gap, cells that never overlap — and a
//  few rendered collages read back pixel by pixel, which is how an
//  upside-down photo or a crop off the subject gets caught.
//

import CoreGraphics
import XCTest
@testable import ImageForge

final class CollageTests: XCTestCase {

    let aspects: [Double] = [1.5, 0.67, 1, 1.78, 0.75, 1.33, 1, 0.8, 1.5]

    // MARK: Spans

    func testSpansMeetBothEdgesWithExactGaps() throws {
        let parts = try CollagePlanner.spans(length: 1001, weights: [1, 2, 3, 1.5], gap: 7, origin: 20)
        XCTAssertEqual(parts.first!.start, 20)
        XCTAssertEqual(parts.last!.start + parts.last!.length, 1021)
        for (a, b) in zip(parts, parts.dropFirst()) {
            XCTAssertEqual(b.start - (a.start + a.length), 7)
        }
    }

    func testSpansRefuseGapsThatLeaveNoRoom() {
        XCTAssertThrowsError(try CollagePlanner.spans(length: 20, weights: [1, 1, 1], gap: 10))
    }

    // MARK: Every layout

    func testNoLayoutOverlapsOrLeavesTheContentArea() throws {
        for layout in CollageLayout.allCases where layout != .polaroid {
            let count = layout == .split ? 3 : aspects.count
            let spec = CollageSpec(layout: layout, width: 1200, height: 900, gap: 10, margin: 30)
            let slots = try CollagePlanner.plan(spec, aspects: Array(aspects.prefix(count)), seed: 1)
            XCTAssertEqual(Set(slots.map(\.index)), Set(0..<count), "\(layout): every photo placed once")
            let content = CGRect(x: 30, y: 30, width: 1140, height: 840)
            for slot in slots {
                XCTAssertTrue(content.contains(slot.rect), "\(layout): \(slot.rect) leaves the content area")
            }
            for (i, a) in slots.enumerated() {
                for b in slots.dropFirst(i + 1) {
                    let overlap = a.rect.intersection(b.rect)
                    XCTAssertTrue(overlap.isNull || overlap.width * overlap.height == 0,
                                  "\(layout): \(a.rect) overlaps \(b.rect)")
                }
            }
        }
    }

    func testMasonryRowsRunEdgeToEdgeAndKeepTheirShape() throws {
        let spec = CollageSpec(layout: .masonry, width: 1600, height: 1200, gap: 12, margin: 0)
        let slots = try CollagePlanner.plan(spec, aspects: aspects, seed: 1)
        let rows = Dictionary(grouping: slots, by: { Int($0.rect.minY) }).values
            .map { $0.sorted { $0.rect.minX < $1.rect.minX } }
        XCTAssertGreaterThan(rows.count, 1)
        for row in rows {
            XCTAssertEqual(row.first!.rect.minX, 0)
            XCTAssertEqual(row.last!.rect.maxX, 1600, "a justified row fills the width exactly")
            for (a, b) in zip(row, row.dropFirst()) { XCTAssertEqual(b.rect.minX - a.rect.maxX, 12) }
            // Widths in proportion to the photos' shapes, to within a pixel
            // of rounding per cell.
            let total = row.reduce(0.0) { $0 + aspects[$1.index] }
            let available = 1600.0 - 12 * Double(row.count - 1)
            for slot in row {
                XCTAssertEqual(Double(slot.rect.width), available * aspects[slot.index] / total, accuracy: 1)
            }
        }
        XCTAssertEqual(slots.map(\.rect.maxY).max(), 1200, "the rows fill the height")
        // Order is kept: reading row by row gives the photos as given.
        let reading = rows.sorted { $0[0].rect.minY < $1[0].rect.minY }.flatMap { $0.map(\.index) }
        XCTAssertEqual(reading, Array(0..<aspects.count))
    }

    func testColumnsShareAWidthAndAStraightBottom() throws {
        let spec = CollageSpec(layout: .columns, width: 1000, height: 1400, gap: 8, margin: 0, columns: 3)
        let slots = try CollagePlanner.plan(spec, aspects: aspects, seed: 1)
        let columns = Dictionary(grouping: slots, by: { Int($0.rect.minX) })
        XCTAssertEqual(columns.count, 3)
        for column in columns.values {
            XCTAssertEqual(Set(column.map { Int($0.rect.width) }).count, 1)
            XCTAssertEqual(column.map(\.rect.maxY).max(), 1400)
        }
    }

    func testFeatureGivesTheHeroTwoThirds() throws {
        let spec = CollageSpec(layout: .feature, width: 1210, height: 800, gap: 10, margin: 0, hero: 2)
        let slots = try CollagePlanner.plan(spec, aspects: Array(aspects.prefix(5)), seed: 1)
        let hero = slots.first { $0.index == 2 }!
        XCTAssertEqual(hero.rect, CGRect(x: 0, y: 0, width: 800, height: 800))
        XCTAssertThrowsError(try CollagePlanner.plan(
            CollageSpec(layout: .feature, hero: 9), aspects: [1, 1], seed: 1))
    }

    func testStripFollowsTheCanvas() throws {
        let tall = try CollagePlanner.plan(CollageSpec(layout: .strip, width: 600, height: 1800, gap: 10, margin: 0),
                                           aspects: [1, 1, 1, 1], seed: 1)
        XCTAssertEqual(Set(tall.map(\.rect.minX)), [0], "a tall canvas stacks")
        let wide = try CollagePlanner.plan(CollageSpec(layout: .strip, width: 1800, height: 600, gap: 10, margin: 0),
                                           aspects: [1, 1, 1, 1], seed: 1)
        XCTAssertEqual(Set(wide.map(\.rect.minY)), [0], "a wide canvas runs across")
    }

    func testSplitTakesTwoToFourAndCanSlant() throws {
        XCTAssertThrowsError(try CollagePlanner.plan(CollageSpec(layout: .split), aspects: [1], seed: 1))
        XCTAssertThrowsError(try CollagePlanner.plan(CollageSpec(layout: .split), aspects: [1, 1, 1, 1, 1], seed: 1))
        let slanted = try CollagePlanner.plan(
            CollageSpec(layout: .split, width: 1000, height: 600, gap: 20, margin: 0, diagonal: true),
            aspects: [1, 1], seed: 1)
        let a = slanted[0].outline!, b = slanted[1].outline!
        XCTAssertEqual(b[0].x - a[1].x, 20, accuracy: 0.001, "the gap holds along the top edge")
        XCTAssertEqual(b[3].x - a[2].x, 20, accuracy: 0.001, "and along the bottom")
    }

    func testPolaroidScatterIsSeededAndStaysOnTheCanvas() throws {
        let spec = CollageSpec(layout: .polaroid, width: 2000, height: 1500, margin: 40)
        let one = try CollagePlanner.plan(spec, aspects: aspects, seed: 42)
        XCTAssertEqual(one, try CollagePlanner.plan(spec, aspects: aspects, seed: 42), "same seed, same scatter")
        XCTAssertNotEqual(one, try CollagePlanner.plan(spec, aspects: aspects, seed: 43))
        for slot in one {
            XCTAssertTrue((-7...7).contains(slot.rotation))
            XCTAssertTrue(CGRect(x: 40, y: 40, width: 1920, height: 1420).contains(slot.rect),
                          "\(slot.rect) leaves the canvas")
            XCTAssertEqual(slot.photo.width, slot.photo.height, accuracy: 0.001, "instant film is square")
            XCTAssertGreaterThan(slot.rect.maxY - slot.photo.maxY, (slot.photo.minY - slot.rect.minY) * 3,
                                 "the bottom border is the thick one")
        }
    }

    func testShuffleIsAPermutationAndRepeatable() {
        let shuffled = CollagePlanner.order(20, .shuffle, seed: 7)
        XCTAssertEqual(shuffled.sorted(), Array(0..<20))
        XCTAssertNotEqual(shuffled, Array(0..<20))
        XCTAssertEqual(shuffled, CollagePlanner.order(20, .shuffle, seed: 7))
        XCTAssertEqual(CollagePlanner.order(5, .asGiven, seed: 7), [0, 1, 2, 3, 4])
    }

    // MARK: Cropping

    func testCropCentresOnTheFocusAndStaysInside() {
        let size = CGSize(width: 4000, height: 2000)
        let centred = CollagePlanner.crop(size, aspect: 1, focus: nil)
        XCTAssertEqual(centred, CGRect(x: 1000, y: 0, width: 2000, height: 2000))
        // A subject far to the right pulls the crop over — to the edge, and
        // no further.
        let right = CollagePlanner.crop(size, aspect: 1, focus: CGPoint(x: 3500, y: 800))
        XCTAssertEqual(right, CGRect(x: 2000, y: 0, width: 2000, height: 2000))
        XCTAssertTrue(right.contains(CGPoint(x: 3500, y: 800)))
        let left = CollagePlanner.crop(size, aspect: 1, focus: CGPoint(x: 1300, y: 800))
        XCTAssertEqual(left.midX, 1300)
    }

    func testFocusKeepsEveryFaceButOnlyTheLargestSalientRegion() {
        let owl = CGRect(x: 9, y: 814, width: 478, height: 472)
        let strays = [CGRect(x: 49, y: 327, width: 142, height: 257), CGRect(x: 503, y: 337, width: 131, height: 426)]
        // Measured on an owl placed bottom-left: objectness also returned two
        // texture patches, and their union centred the crop above its head.
        XCTAssertEqual(CollagePlanner.focus(strays + [owl], kind: .object), owl)
        let faces = [CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 90, y: 0, width: 10, height: 10)]
        XCTAssertEqual(CollagePlanner.focus(faces, kind: .face), CGRect(x: 0, y: 0, width: 100, height: 10))
        XCTAssertNil(CollagePlanner.focus([], kind: .attention))
    }

    func testASpecRoundTripsAsReadableJSON() throws {
        let spec = CollageSpec(layout: .polaroid, background: .color(ForgeColor(hex: "#2B2B2B")!), seed: 5)
        let json = String(decoding: try JSONEncoder().encode(spec), as: UTF8.self)
        XCTAssertTrue(json.contains(##""background":{"color":"#2B2B2B"}"##), json)
        XCTAssertEqual(try JSONDecoder().decode(CollageSpec.self, from: Data(json.utf8)), spec)
        let image = CollageSpec(background: .image(URL(fileURLWithPath: "/tmp/bg.jpg")))
        XCTAssertEqual(try JSONDecoder().decode(CollageSpec.self, from: try JSONEncoder().encode(image)), image)
    }

    // MARK: Pixels

    func testRenderedCellsHoldTheirPhotosTheRightWayUp() async throws {
        let folder = TestImages.temporaryDirectory()
        defer { try? FileManager.default.removeAll(at: folder) }
        // Red over blue: an upside-down draw puts the blue on top.
        let topRed = TestImages.make(Array(repeating: Array(repeating: .red, count: 40), count: 20)
                                     + Array(repeating: Array(repeating: .blue, count: 40), count: 20))
        var files: [URL] = []
        for (i, image) in [topRed, TestImages.solid(.green, width: 40, height: 40),
                           TestImages.solid(.black, width: 40, height: 40),
                           TestImages.solid(.blue, width: 40, height: 40)].enumerated() {
            let url = folder.appendingPathComponent("p\(i).png")
            _ = try ImageEncoder.write(try ImageEncoder.encode(image, format: .png, spec: EncodeSpec()),
                                       to: url, overwrites: true)
            files.append(url)
        }
        let spec = CollageSpec(layout: .grid, width: 210, height: 210, gap: 10, margin: 0, fit: .fit)
        let (image, result) = try await ImageForge.collage(files, spec: spec)
        XCTAssertEqual(result.cells.count, 4)
        XCTAssertTrue(TestImages.pixel(image, x: 50, y: 20).isClose(to: .red), "the top of the first photo is red")
        XCTAssertTrue(TestImages.pixel(image, x: 50, y: 80).isClose(to: .blue))
        XCTAssertTrue(TestImages.pixel(image, x: 160, y: 50).isClose(to: .green))
        XCTAssertTrue(TestImages.pixel(image, x: 50, y: 160).isClose(to: .black))
        XCTAssertTrue(TestImages.pixel(image, x: 105, y: 50).isClose(to: .white), "the gap shows the background")
    }

    func testAWrittenCollageReportsWhereEveryPhotoWent() async throws {
        let folder = TestImages.temporaryDirectory()
        defer { try? FileManager.default.removeAll(at: folder) }
        var files: [URL] = []
        for i in 0..<5 {
            let url = folder.appendingPathComponent("photo-\(i).png")
            _ = try ImageEncoder.write(try ImageEncoder.encode(TestImages.noise(width: 60 + i * 20, height: 60, seed: UInt64(i + 1)),
                                                               format: .png, spec: EncodeSpec()),
                                       to: url, overwrites: true)
            files.append(url)
        }
        let out = folder.appendingPathComponent("collage.jpg")
        let result = try await ImageForge.collage(files, to: out,
                                                  spec: CollageSpec(layout: .polaroid, width: 800, height: 600,
                                                                    seed: 9, captions: true))
        XCTAssertEqual(result.seed, 9)
        XCTAssertEqual(result.format, .jpeg)
        XCTAssertGreaterThan(result.bytes, 0)
        XCTAssertEqual(Set(result.cells.map(\.source)), Set(0..<5))
        XCTAssertEqual(try ImageForge.describe(out).width, 800)
    }
}

private extension FileManager {
    func removeAll(at url: URL) throws { try removeItem(at: url) }
}
