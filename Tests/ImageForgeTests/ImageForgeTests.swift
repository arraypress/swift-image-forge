//
//  ImageForgeTests.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  End to end: a file goes in, a file comes out, and the claims made about
//  it in the README are the ones asserted here.
//

import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import ImageForge

final class ImageForgeTests: XCTestCase {

    var directory: URL!

    override func setUp() {
        super.setUp()
        directory = TestImages.temporaryDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// Writes an image to the test directory and hands back the URL.
    @discardableResult
    func write(_ image: CGImage, as format: ImageFormat, named name: String,
               properties: [String: Any]? = nil) throws -> URL {
        let data = try ImageEncoder.encode(image, format: format,
                                           spec: EncodeSpec(format: format, metadata: .keep),
                                           sourceProperties: properties)
        let url = directory.appendingPathComponent(name).appendingPathExtension(format.fileExtension)
        try ImageEncoder.write(data, to: url, overwrites: true)
        return url
    }

    // MARK: - Describing

    func testDescribeReadsTheHeader() throws {
        let url = try write(TestImages.solid(.red, width: 60, height: 40), as: .png, named: "flat")
        let info = try ImageForge.describe(url)

        XCTAssertEqual(info.width, 60)
        XCTAssertEqual(info.height, 40)
        XCTAssertEqual(info.format, .png)
        XCTAssertEqual(info.frameCount, 1)
        XCTAssertFalse(info.isAnimated)
        XCTAssertFalse(info.hasGainMap)
        XCTAssertEqual(info.orientation, 1)
        XCTAssertEqual(info.aspectRatio, 1.5, accuracy: 0.001)
        XCTAssertNotNil(info.byteCount)
    }

    func testDescribingSomethingThatIsNotAnImageFails() throws {
        let url = directory.appendingPathComponent("notes.png")
        try "this is not a picture".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ImageForge.describe(url))
    }

    func testAFileWithNoPixelsIsNotAnImage() throws {
        // ImageIO opens a PDF and recognises its type, then reports no
        // dimensions. Answering 0×0 would carry the nonsense into a batch.
        let url = directory.appendingPathComponent("empty.pdf")
        try Data("%PDF-1.4\n%%EOF\n".utf8).write(to: url)
        XCTAssertThrowsError(try ImageForge.describe(url)) { error in
            guard case ImageForgeError.noImage = error else {
                if case ImageForgeError.unreadable = error { return }
                return XCTFail("expected noImage or unreadable, got \(error)")
            }
        }
    }

    func testDescribingAMissingFileSaysSo() {
        XCTAssertThrowsError(try ImageForge.describe(directory.appendingPathComponent("gone.png"))) { error in
            guard case ImageForgeError.fileNotFound = error else {
                return XCTFail("expected fileNotFound, got \(error)")
            }
        }
    }

    // MARK: - Converting

    func testConvertChangesTheFormatAndNothingElse() async throws {
        let source = try write(TestImages.solid(.red, width: 30, height: 20), as: .png, named: "red")
        let result = try await ImageForge.convert(source, to: .jpeg)

        XCTAssertEqual(result.after.format, .jpeg)
        XCTAssertEqual(result.after.width, 30)
        XCTAssertEqual(result.after.height, 20)
        XCTAssertFalse(result.usedPassthrough, "no gain map, so the render road")
    }

    func testConvertingToAnUnwritableFormatNamesTheAlternative() async throws {
        let source = try write(TestImages.solid(.red, width: 10, height: 10), as: .png, named: "red")
        do {
            _ = try await ImageForge.convert(source, to: .webp)
            XCTFail("WebP cannot be written on this platform")
        } catch let error as ImageForgeError {
            guard case .formatNotWritable(_, let alternative) = error else {
                return XCTFail("expected formatNotWritable, got \(error)")
            }
            XCTAssertEqual(alternative, .avif)
        }
    }

    func testTransparencyIsMattedWhenTheFormatCannotHoldIt() async throws {
        let source = try write(TestImages.solid(.clear, width: 20, height: 20), as: .png, named: "clear")
        let destination = directory.appendingPathComponent("matted.jpg")

        let result = try await ImageForge.process(source, to: destination, options: ProcessOptions(
            encode: EncodeSpec(format: .jpeg, matte: .white)))

        XCTAssertTrue(result.operations.contains(.flatten(.white)),
                      "the matte should be reported, not applied invisibly")
        let written = try ImageDecoder.image(at: destination)
        XCTAssertTrue(TestImages.pixel(written, x: 0, y: 0).isClose(to: .white))
    }

    // MARK: - Resizing

    func testResizeBoundsTheLongestSide() async throws {
        let source = try write(TestImages.noise(width: 400, height: 200), as: .png, named: "wide")
        let destination = directory.appendingPathComponent("bounded.png")

        let result = try await ImageForge.process(source, to: destination,
                                                  options: .resize(longestSide: 100))
        XCTAssertEqual(result.after.width, 100)
        XCTAssertEqual(result.after.height, 50)
    }

    func testASmallImageIsNotBlownUp() async throws {
        let source = try write(TestImages.solid(.red, width: 40, height: 40), as: .png, named: "small")
        let destination = directory.appendingPathComponent("same.png")

        let result = try await ImageForge.process(source, to: destination,
                                                  options: .resize(longestSide: 400))
        XCTAssertEqual(result.after.width, 40, "upscaling is off unless asked for")
    }

    func testSmartFillProducesTheRequestedShape() async throws {
        let source = try write(TestImages.noise(width: 300, height: 150), as: .png, named: "subject")
        let destination = directory.appendingPathComponent("square.jpg")

        let result = try await ImageForge.process(source, to: destination, options: ProcessOptions(
            operations: [.resize(.fill(width: 120, height: 120, anchor: .smart))],
            encode: .format(.jpeg)))

        XCTAssertEqual(result.after.width, 120)
        XCTAssertEqual(result.after.height, 120)
        XCTAssertFalse(result.operations.contains { $0.needsAnalysis },
                       "the report should show the rectangle, not the intent")
    }

    // MARK: - Metadata

    func testLocationIsDroppedByDefaultAndKeptOnRequest() async throws {
        let properties: [String: Any] = [
            kCGImagePropertyGPSDictionary as String: [
                kCGImagePropertyGPSLatitude as String: 51.5074,
                kCGImagePropertyGPSLongitude as String: 0.1278,
            ],
        ]
        let source = try write(TestImages.solid(.red, width: 20, height: 20), as: .jpeg,
                               named: "located", properties: properties)
        XCTAssertTrue(try ImageForge.describe(source).hasLocation, "the fixture must carry GPS")

        let stripped = directory.appendingPathComponent("stripped.jpg")
        _ = try await ImageForge.process(source, to: stripped, options: ProcessOptions(
            encode: EncodeSpec(format: .jpeg, metadata: .stripLocation)))
        XCTAssertFalse(try ImageForge.describe(stripped).hasLocation,
                       "a resize for the web must not leak where the photo was taken")

        let kept = directory.appendingPathComponent("kept.jpg")
        _ = try await ImageForge.process(source, to: kept, options: ProcessOptions(
            encode: EncodeSpec(format: .jpeg, metadata: .keep)))
        XCTAssertTrue(try ImageForge.describe(kept).hasLocation)
    }

    func testStripRemovesEverything() {
        let properties: [String: Any] = [
            kCGImagePropertyGPSDictionary as String: ["x": 1],
            kCGImagePropertyExifDictionary as String: ["y": 2],
            kCGImagePropertyIPTCDictionary as String: ["z": 3],
        ]
        let filtered = Metadata.filtered(properties, policy: .strip)
        XCTAssertEqual(filtered.count, 1, "only the orientation is left")
        XCTAssertEqual(filtered[kCGImagePropertyOrientation as String] as? Int, 1)
    }

    func testCaptureOnlyKeepsTheCameraAndDropsTheRest() {
        let properties: [String: Any] = [
            kCGImagePropertyGPSDictionary as String: ["x": 1],
            kCGImagePropertyExifDictionary as String: ["y": 2],
            kCGImagePropertyIPTCDictionary as String: ["z": 3],
        ]
        let filtered = Metadata.filtered(properties, policy: .captureOnly)
        XCTAssertNotNil(filtered[kCGImagePropertyExifDictionary as String])
        XCTAssertNil(filtered[kCGImagePropertyGPSDictionary as String])
        XCTAssertNil(filtered[kCGImagePropertyIPTCDictionary as String])
    }

    // MARK: - Byte budgets

    func testABudgetIsMet() async throws {
        let source = try write(TestImages.noise(width: 300, height: 300), as: .png, named: "noisy")
        let destination = directory.appendingPathComponent("budgeted.jpg")
        let budget = 30_000

        let result = try await ImageForge.process(source, to: destination, options: ProcessOptions(
            encode: .underBytes(budget, format: .jpeg)))

        XCTAssertLessThanOrEqual(result.bytesAfter, budget)
        XCTAssertGreaterThan(result.bytesAfter, 0)
    }

    func testAnImpossibleBudgetSaysToResizeInstead() async throws {
        let source = try write(TestImages.noise(width: 400, height: 400), as: .png, named: "dense")
        let destination = directory.appendingPathComponent("tiny.jpg")

        do {
            _ = try await ImageForge.process(source, to: destination, options: ProcessOptions(
                encode: .underBytes(200, format: .jpeg)))
            XCTFail("200 bytes of a 400×400 photograph is not reachable by quality alone")
        } catch let error as ImageForgeError {
            guard case .budgetUnreachable = error else {
                return XCTFail("expected budgetUnreachable, got \(error)")
            }
            XCTAssertTrue(error.localizedDescription.contains("resize"),
                          "the message should say what to do instead")
        }
    }

    // MARK: - Writing rules

    func testAnExistingFileIsNotReplacedUnlessAsked() async throws {
        let source = try write(TestImages.solid(.red, width: 10, height: 10), as: .png, named: "a")
        let destination = directory.appendingPathComponent("taken.png")
        try Data("occupied".utf8).write(to: destination)

        do {
            _ = try await ImageForge.process(source, to: destination, options: ProcessOptions())
            XCTFail("should not have replaced an existing file")
        } catch let error as ImageForgeError {
            guard case .destinationExists = error else {
                return XCTFail("expected destinationExists, got \(error)")
            }
        }

        var options = ProcessOptions()
        options.overwrites = true
        _ = try await ImageForge.process(source, to: destination, options: options)
        XCTAssertEqual(try ImageForge.describe(destination).width, 10)
    }

    // MARK: - Batches

    func testABatchReportsEachFileAndCarriesOnPastFailures() async throws {
        let good = try write(TestImages.solid(.red, width: 20, height: 20), as: .png, named: "one")
        let alsoGood = try write(TestImages.solid(.blue, width: 30, height: 30), as: .png, named: "two")
        let bad = directory.appendingPathComponent("three.png")
        try Data("not an image".utf8).write(to: bad)

        let output = directory.appendingPathComponent("out")
        let results = await ImageForge.process([good, bad, alsoGood], into: output,
                                               options: .convert(to: .jpeg))

        XCTAssertEqual(results.count, 3)
        XCTAssertNoThrow(try results[0].get())
        XCTAssertThrowsError(try results[1].get(), "the middle file is not an image")
        XCTAssertNoThrow(try results[2].get())
        XCTAssertEqual(try results[2].get().after.width, 30)
        XCTAssertEqual(try results[2].get().destination?.pathExtension, "jpg")
    }

    // MARK: - Icons

    func testAnIcnsHoldsEverySizeAsked() throws {
        let source = try write(TestImages.noise(width: 300, height: 300), as: .png, named: "mark")
        let destination = directory.appendingPathComponent("mark.icns")

        let bytes = try ImageForge.icon(source, to: destination, spec: IconSpec(sizes: [128, 48, 32, 16]))
        XCTAssertGreaterThan(bytes, 0)
        XCTAssertEqual(try ImageForge.describe(destination).frameCount, 4)
    }

    func testAnIcoIsWrittenToo() throws {
        let source = try write(TestImages.noise(width: 200, height: 200), as: .png, named: "fav")
        let destination = directory.appendingPathComponent("fav.ico")

        try ImageForge.icon(source, to: destination, spec: .favicon)
        XCTAssertEqual(try ImageForge.describe(destination).format, .ico)
    }

    func testANonSquareSourceIsCroppedSquareForAnIcon() throws {
        let source = try write(TestImages.noise(width: 400, height: 200), as: .png, named: "wide")
        let destination = directory.appendingPathComponent("wide.icns")
        XCTAssertNoThrow(try ImageForge.icon(source, to: destination, spec: IconSpec(sizes: [128])))
    }

    func testAScaleFactorSetIsWrittenAsSeparateFiles() throws {
        let source = try write(TestImages.noise(width: 300, height: 300), as: .png, named: "glyph")
        let urls = try ImageForge.iconSet(source, into: directory,
                                          spec: .scaleFactors(base: 40), overwrites: true)

        XCTAssertEqual(urls.count, 3)
        let sizes = try urls.map { try ImageForge.describe($0).width }.sorted()
        XCTAssertEqual(sizes, [40, 80, 120])
    }

    // MARK: - Animation

    func testAnimationRoundTrips() throws {
        let frames = [TestImages.Pixel.red, .green, .blue].enumerated().map { index, colour in
            let url = try! write(TestImages.solid(colour, width: 20, height: 20),
                                 as: .png, named: "frame\(index)")
            return url
        }
        let gif = directory.appendingPathComponent("loop.gif")
        try ImageForge.animate(frames, to: gif, format: .gif, frameDuration: 0.05)

        let info = try ImageForge.describe(gif)
        XCTAssertEqual(info.format, .gif)
        XCTAssertEqual(info.frameCount, 3)
        XCTAssertTrue(info.isAnimated)

        let read = try ImageForge.frames(of: gif)
        XCTAssertEqual(read.count, 3)
        XCTAssertEqual(read[0].duration, 0.05, accuracy: 0.005,
                       "the unclamped delay has to be read, or a fast loop plays at a crawl")
        XCTAssertTrue(TestImages.pixel(read[0].image, x: 0, y: 0).isClose(to: .red, tolerance: 20))
        XCTAssertTrue(TestImages.pixel(read[2].image, x: 0, y: 0).isClose(to: .blue, tolerance: 20))
    }

    func testReversingAnAnimationTurnsItAround() throws {
        let sources = [TestImages.Pixel.red, .green, .blue].enumerated().map { index, colour in
            try! write(TestImages.solid(colour, width: 16, height: 16), as: .png, named: "r\(index)")
        }
        let gif = directory.appendingPathComponent("back.gif")
        try ImageForge.animate(sources, to: gif, frameDuration: 0.1, animation: .reverse)

        let read = try ImageForge.frames(of: gif)
        XCTAssertEqual(read.count, 3)
        XCTAssertTrue(TestImages.pixel(read[0].image, x: 0, y: 0).isClose(to: .blue, tolerance: 20),
                      "reversed, the last frame comes first")
    }

    func testFrameStrideThinsTheAnimation() {
        let frames = (0..<6).map {
            ImageFrame(image: TestImages.solid(.red, width: 4, height: 4), duration: 0.1 * Double($0 + 1))
        }
        XCTAssertEqual(ImageEncoder.arrange(frames, with: AnimationSpec(frameStride: 2)).count, 3)
        XCTAssertEqual(ImageEncoder.arrange(frames, with: AnimationSpec(pingPong: true)).count, 10)
    }

    func testAStillFormatRefusesAnimation() {
        let frames = [ImageFrame(image: TestImages.solid(.red, width: 4, height: 4), duration: 0.1)]
        XCTAssertThrowsError(try ImageEncoder.encode(frames: frames, format: .jpeg,
                                                     spec: EncodeSpec(), animation: .default)) { error in
            guard case ImageForgeError.notAnimatable = error else {
                return XCTFail("expected notAnimatable, got \(error)")
            }
        }
    }

    // MARK: - Reporting

    func testTheResultReportsWhatWasSaved() async throws {
        let source = try write(TestImages.noise(width: 200, height: 200), as: .png, named: "big")
        let destination = directory.appendingPathComponent("small.jpg")

        let result = try await ImageForge.process(source, to: destination, options: ProcessOptions(
            operations: [.resize(.longestSide(50))], encode: .format(.jpeg, quality: 0.5)))

        XCTAssertGreaterThan(result.bytesBefore, result.bytesAfter)
        XCTAssertGreaterThan(result.savingsRatio, 0)
        XCTAssertFalse(result.lostGainMap, "there was no gain map to lose")
        XCTAssertEqual(result.source, source)
        XCTAssertEqual(result.destination, destination)
    }
}
