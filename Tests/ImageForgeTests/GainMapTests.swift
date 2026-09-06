//
//  GainMapTests.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  The claim that cannot be checked by looking at the picture.
//
//  A gain map is not part of a `CGImage`. Decode, do anything, encode, and
//  it is gone — the result still looks fine on an ordinary display, which
//  is exactly why the loss goes unnoticed. These tests build a file that
//  really has one, put it through both roads, and check the answer against
//  the file on disk rather than against what the library says it did.
//

import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import ImageForge

final class GainMapTests: XCTestCase {

    var directory: URL!
    var source: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = TestImages.temporaryDirectory()
        source = directory.appendingPathComponent("hdr.heic")
        try TestImages.writeGainMapHEIC(to: source, width: 200, height: 100)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// Whether the file on disk really carries a gain map.
    func fileHasGainMap(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return ImageDecoder.hasGainMap(source)
    }

    func testTheFixtureItselfHasAGainMap() throws {
        XCTAssertTrue(fileHasGainMap(source), "the rest of this file tests nothing without it")
        XCTAssertTrue(try ImageForge.describe(source).hasGainMap)
    }

    func testAResizeKeepsTheGainMap() async throws {
        let destination = directory.appendingPathComponent("small.heic")
        let result = try await ImageForge.process(source, to: destination, options: ProcessOptions(
            operations: [.resize(.longestSide(100))],
            encode: EncodeSpec(format: .heic, hdr: .preserve)))

        XCTAssertTrue(result.usedPassthrough, "a plain downscale should take the fast road")
        XCTAssertTrue(result.gainMapPreserved)
        XCTAssertFalse(result.lostGainMap)
        XCTAssertTrue(fileHasGainMap(destination), "and the file itself must still have one")
        XCTAssertEqual(result.after.width, 100, "while actually being resized")
        XCTAssertEqual(result.after.height, 50)
    }

    func testAFormatChangeKeepsTheGainMap() async throws {
        let destination = directory.appendingPathComponent("converted.avif")
        let result = try await ImageForge.convert(source, to: .avif, destination: destination)

        XCTAssertTrue(result.usedPassthrough)
        XCTAssertTrue(fileHasGainMap(destination), "AVIF can hold a gain map, so it should still be there")
    }

    func testACropLosesTheGainMapAndSaysSo() async throws {
        let destination = directory.appendingPathComponent("cropped.heic")
        let result = try await ImageForge.process(source, to: destination, options: ProcessOptions(
            operations: [.crop(.square())],
            encode: EncodeSpec(format: .heic, hdr: .preserve)))

        // A crop needs the pixels, so there is no way to keep the map. The
        // point is that this is reported rather than hidden.
        XCTAssertFalse(result.usedPassthrough)
        XCTAssertFalse(result.gainMapPreserved)
        XCTAssertTrue(result.lostGainMap, "the caller asked to preserve and did not get it")
        XCTAssertFalse(fileHasGainMap(destination))
    }

    func testAFormatThatCannotHoldOneLosesIt() async throws {
        let destination = directory.appendingPathComponent("flat.png")
        let result = try await ImageForge.convert(source, to: .png, destination: destination)

        XCTAssertFalse(result.usedPassthrough, "PNG holds no gain map, so there is no fast road")
        XCTAssertTrue(result.lostGainMap)
        XCTAssertFalse(fileHasGainMap(destination))
    }

    func testTonemappingDropsTheMapOnPurpose() async throws {
        let destination = directory.appendingPathComponent("sdr.heic")
        let result = try await ImageForge.process(source, to: destination, options: ProcessOptions(
            encode: EncodeSpec(format: .heic, hdr: .tonemap)))

        XCTAssertFalse(result.gainMapPreserved, "tone mapping means baking it in, not keeping it")
        XCTAssertFalse(fileHasGainMap(destination))
    }

    func testDiscardingTakesTheRenderRoad() async throws {
        let destination = directory.appendingPathComponent("discarded.heic")
        let result = try await ImageForge.process(source, to: destination, options: ProcessOptions(
            encode: EncodeSpec(format: .heic, hdr: .discard)))

        XCTAssertFalse(result.usedPassthrough)
        XCTAssertFalse(fileHasGainMap(destination))
    }

    func testAByteBudgetForcesTheRenderRoad() async throws {
        // The budget search re-encodes to measure, which a passthrough
        // cannot do, so the fast road is closed however much we would like it.
        let destination = directory.appendingPathComponent("budgeted.heic")
        let result = try await ImageForge.process(source, to: destination, options: ProcessOptions(
            encode: .underBytes(50_000, format: .heic)))

        XCTAssertFalse(result.usedPassthrough)
        XCTAssertLessThanOrEqual(result.bytesAfter, 50_000)
    }

    func testAnImageWithNoGainMapNeverClaimsToHaveLostOne() async throws {
        let plain = directory.appendingPathComponent("plain.png")
        let data = try ImageEncoder.encode(TestImages.solid(.red, width: 40, height: 40),
                                           format: .png, spec: EncodeSpec(format: .png))
        try ImageEncoder.write(data, to: plain, overwrites: true)

        let result = try await ImageForge.convert(plain, to: .heic,
                                                  destination: directory.appendingPathComponent("plain.heic"))
        XCTAssertFalse(result.before.hasGainMap)
        XCTAssertFalse(result.lostGainMap, "nothing was lost, because there was nothing to lose")
    }
}
