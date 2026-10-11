//
//  RegionGradeTests.swift
//  ImageForgeTests
//
//  Created by David Sherlock on 2026.
//
//  A grade inside a region: graded where the mask is, untouched — byte for
//  byte — everywhere else, through the whole process() road an 8-bit PNG
//  takes. The resolver here is a stub; the real one is SAM 3, in img.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import VideoGrade
import XCTest
@testable import ImageForge

final class RegionGradeTests: XCTestCase {

    /// A noisy 64×48 picture, so an identical half cannot be luck.
    private func source() throws -> URL {
        let url = TestImages.temporaryDirectory().appendingPathComponent("region-\(UUID().uuidString).png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, TestImages.noise(width: 64, height: 48), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// The left half, 255; the right, 0.
    private func leftHalf(width: Int = 64, height: Int = 48) -> RegionMask {
        var bytes = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height { for x in 0..<(width / 2) { bytes[y * width + x] = 255 } }
        return RegionMask(width: width, height: height, pixels: Data(bytes), feather: 0)
    }

    private func bright() -> VideoGrade {
        var grade = VideoGrade()
        grade.exposure = 1
        return grade
    }

    private func decoded(_ url: URL) throws -> [[TestImages.Pixel]] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return TestImages.read(try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil)))
    }

    func testOutsideTheMaskIsByteIdenticalAndInsideIsGraded() async throws {
        let input = try source()
        let output = input.deletingLastPathComponent().appendingPathComponent("graded-\(UUID().uuidString).png")
        let mask = leftHalf()
        var options = ProcessOptions(operations: [.gradeWithin(bright(), .named("left", minimumScore: 0.6, feather: 0))])
        options.encode.format = .png
        let asked = LockedNames()
        try await ImageForge.process(input, to: output, options: options) { name, image, minimumScore in
            await asked.add("\(name)@\(minimumScore) \(image.width)×\(image.height)")
            return mask
        }
        let before = try decoded(input), after = try decoded(output)
        var outsideChanged = 0, insideBrighter = 0, inside = 0
        for y in 0..<48 {
            for x in 0..<64 {
                if x < 32 {
                    inside += 1
                    if Int(after[y][x].r) + Int(after[y][x].g) + Int(after[y][x].b)
                        > Int(before[y][x].r) + Int(before[y][x].g) + Int(before[y][x].b) { insideBrighter += 1 }
                } else if after[y][x] != before[y][x] { outsideChanged += 1 }
            }
        }
        print("REGION: outside pixels changed \(outsideChanged) of \(64 * 48 - inside); inside brighter \(insideBrighter) of \(inside)")
        XCTAssertEqual(outsideChanged, 0, "outside the mask must be byte-identical")
        XCTAssertGreaterThan(Double(insideBrighter) / Double(inside), 0.95, "+1 stop brightens the region")
        let names = await asked.names
        XCTAssertEqual(names, ["left@0.6 64×48"], "the resolver is asked once, on the picture, with the floor")
    }

    func testAFeatheredEdgeFadesAcrossTheBoundary() throws {
        let image = TestImages.solid(.init(r: 100, g: 100, b: 100, a: 255), width: 64, height: 48)
        var mask = leftHalf()
        mask = RegionMask(width: mask.width, height: mask.height, pixels: mask.pixels, feather: 12)
        let out = TestImages.read(try Pipeline.apply([.gradeWithin(bright(), .mask(mask))], to: image))
        let row = out[24].map { Int($0.r) }
        // Deep inside: fully graded; deep outside: the original; across the
        // edge: in between, never stepping back.
        XCTAssertGreaterThan(row[2], 150)
        XCTAssertEqual(row[63], 100)
        XCTAssertTrue((28..<36).contains { row[$0] > 100 && row[$0] < row[2] }, "a soft edge, not a step: \(row[24..<40])")
        XCTAssertTrue(zip(row, row.dropFirst()).allSatisfy { $0 >= $1 }, "monotone across the edge")
    }

    func testANamedRegionNeedsAResolverAndANameThatIsThere() async throws {
        let input = try source()
        var options = ProcessOptions(operations: [.gradeWithin(bright(), .named("sky", minimumScore: 0.6, feather: 4))])
        options.encode.format = .png
        do {
            _ = try await ImageForge.process(input, options: options)
            XCTFail("a name with no resolver")
        } catch ImageForgeError.requiresAsynchronousProcessing {}
        do {
            _ = try await ImageForge.process(input, options: options) { _, _, _ in nil }
            XCTFail("a name that is not there")
        } catch ImageForgeError.emptyResult(let why) {
            XCTAssertTrue(why.contains("sky"), why)
        }
        XCTAssertTrue(ImageOperation.gradeWithin(bright(), .named("sky", minimumScore: 0.6, feather: 4)).needsAnalysis)
        XCTAssertFalse(ImageOperation.gradeWithin(bright(), .mask(leftHalf())).needsAnalysis)
    }

    func testARecipeKeepsTheNameNotThePixels() throws {
        let operation = ImageOperation.gradeWithin(bright(), .named("sky", minimumScore: 0.7, feather: 6))
        let data = try JSONEncoder().encode(operation)
        XCTAssertEqual(try JSONDecoder().decode(ImageOperation.self, from: data), operation)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("sky"))
        XCTAssertEqual(operation.summary, "grade within sky")
    }
}

/// Collects what the resolver was asked, across its concurrency domain.
private actor LockedNames {
    var names: [String] = []
    func add(_ name: String) { names.append(name) }
}
