//
//  PipelineTests.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Operations compose in the order they are given, and the order changes
//  the answer — which is the argument for a list of steps rather than a
//  struct of settings.
//

import CoreGraphics
import XCTest
@testable import ImageForge

final class PipelineTests: XCTestCase {

    func testStepsAreAppliedInOrder() throws {
        let image = TestImages.solid(.red, width: 100, height: 50)

        let cropThenResize = try Pipeline.apply([
            .crop(.rect(x: 0, y: 0, width: 50, height: 50)),
            .resize(ResizeSpec(width: 20, height: 20)),
        ], to: image)
        XCTAssertEqual(cropThenResize.pixelSize, CGSize(width: 20, height: 20))

        let resizeThenCrop = try Pipeline.apply([
            .resize(ResizeSpec(width: 20, height: 20)),
            .crop(.rect(x: 0, y: 0, width: 5, height: 5)),
        ], to: image)
        XCTAssertEqual(resizeThenCrop.pixelSize, CGSize(width: 5, height: 5),
                       "the same two steps the other way round give a different picture")
    }

    func testRotationAndPadCompose() throws {
        let image = TestImages.solid(.red, width: 4, height: 2)
        let result = try Pipeline.apply([
            .rotate(.ninety),
            .pad(.all(1, color: .black)),
        ], to: image)
        XCTAssertEqual(result.pixelSize, CGSize(width: 4, height: 6),
                       "2×4 after the turn, plus one pixel on each edge")
    }

    func testFlattenRemovesAlpha() throws {
        let image = TestImages.solid(.clear, width: 2, height: 2)
        XCTAssertTrue(image.hasAlphaChannel)
        let result = try Pipeline.apply([.flatten(.white)], to: image)
        XCTAssertFalse(result.hasAlphaChannel)
    }

    func testTrimTransparentFindsTheContent() throws {
        // A single red pixel adrift in a 5×5 field of nothing.
        var rows = Array(repeating: Array(repeating: TestImages.Pixel.clear, count: 5), count: 5)
        rows[1][3] = .red
        let image = TestImages.make(rows)

        let trimmed = try Pipeline.apply([.crop(.trimTransparent(tolerance: 0))], to: image)
        XCTAssertEqual(trimmed.pixelSize, CGSize(width: 1, height: 1))
        XCTAssertTrue(TestImages.pixel(trimmed, x: 0, y: 0).isClose(to: .red))
    }

    func testTrimmingAFullyTransparentImageIsRefused() {
        let image = TestImages.solid(.clear, width: 4, height: 4)
        XCTAssertThrowsError(try Pipeline.apply([.crop(.trimTransparent(tolerance: 0))], to: image)) { error in
            guard case ImageForgeError.emptyResult = error else {
                return XCTFail("expected emptyResult, got \(error)")
            }
        }
    }

    func testAlphaTrimReportsTheOccupiedRectangle() throws {
        var rows = Array(repeating: Array(repeating: TestImages.Pixel.clear, count: 6), count: 4)
        rows[1][2] = .red
        rows[2][4] = .blue
        let rect = try AlphaTrim.contentRect(of: TestImages.make(rows))
        XCTAssertEqual(rect, CGRect(x: 2, y: 1, width: 3, height: 2))
    }

    func testAnImageWithNoAlphaIsAllContent() throws {
        let rect = try AlphaTrim.contentRect(of: TestImages.solid(.red, width: 3, height: 2))
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 3, height: 2))
    }

    func testSmartCropRefusesTheSynchronousPath() {
        let image = TestImages.solid(.red, width: 10, height: 10)
        XCTAssertThrowsError(try Pipeline.apply([.crop(.square(anchor: .smart))], to: image)) { error in
            guard case ImageForgeError.requiresAsynchronousProcessing = error else {
                return XCTFail("expected requiresAsynchronousProcessing, got \(error)")
            }
        }
    }

    func testResolvingASmartCropLeavesAPlainRectangle() async throws {
        let image = TestImages.noise(width: 120, height: 80)
        let resolved = try Pipeline.resolve([.crop(.square(anchor: .smart))], for: image,
                                        subject: Subject(rect: CGRect(x: 50, y: 30, width: 20, height: 20),
                                                         kind: .face, count: 1))

        XCTAssertEqual(resolved.count, 1)
        guard case .crop(.rect(_, _, let width, let height)) = resolved[0] else {
            return XCTFail("a resolved smart crop should be a plain rectangle, got \(resolved[0])")
        }
        XCTAssertEqual(width, 80)
        XCTAssertEqual(height, 80)
        XCTAssertFalse(resolved.contains { $0.needsAnalysis })

        // And it runs synchronously now.
        let cropped = try Pipeline.apply(resolved, to: image)
        XCTAssertEqual(cropped.pixelSize, CGSize(width: 80, height: 80))
    }

    func testResolvingASmartFillBecomesAScaleAndACrop() async throws {
        let image = TestImages.noise(width: 200, height: 100)
        let resolved = try Pipeline.resolve(
            [.resize(.fill(width: 50, height: 50, anchor: .smart))], for: image,
            subject: Subject(rect: CGRect(x: 90, y: 40, width: 20, height: 20),
                             kind: .face, count: 1))

        XCTAssertEqual(resolved.count, 2, "a smart fill is a scale then a crop")
        let result = try Pipeline.apply(resolved, to: image)
        XCTAssertEqual(result.pixelSize, CGSize(width: 50, height: 50))
    }

    func testAFixedAnchorFillReportsItsRectangleToo() async throws {
        // The same logical operation should report the same way whether or
        // not Vision was involved; a caller asking "what did you keep?"
        // should not have to know which anchor was used.
        let image = TestImages.noise(width: 200, height: 100)
        let resolved = try Pipeline.resolve(
            [.resize(.fill(width: 50, height: 50, anchor: .center))], for: image)

        XCTAssertEqual(resolved.count, 2)
        guard case .crop(.rect(let x, _, let width, let height)) = resolved[1] else {
            return XCTFail("a fill should resolve to a scale and a rectangle, got \(resolved)")
        }
        XCTAssertEqual(width, 50)
        XCTAssertEqual(height, 50)
        XCTAssertEqual(x, 25, "centred in the 100-wide scaled image")
        XCTAssertEqual(try Pipeline.apply(resolved, to: image).pixelSize, CGSize(width: 50, height: 50))
    }

    func testAFillThatNeedsNoCropIsNotSplit() async throws {
        // Already the right shape: there is no overflow to give back, so the
        // operation stays one step.
        let image = TestImages.noise(width: 100, height: 100)
        let resolved = try Pipeline.resolve(
            [.resize(.fill(width: 50, height: 50, anchor: .center))], for: image)
        XCTAssertEqual(resolved.count, 1)
    }

    func testResolvingLeavesOrdinaryOperationsAlone() async throws {
        let operations: [ImageOperation] = [.resize(.longestSide(50)), .rotate(.ninety)]
        let resolved = try Pipeline.resolve(operations, for: TestImages.solid(.red, width: 10, height: 10))
        XCTAssertEqual(resolved, operations)
    }

    func testOrientationMapsToTheRightTurns() {
        XCTAssertEqual(Orientation.operations(for: 1), [])
        XCTAssertEqual(Orientation.operations(for: 6), [.rotate(.ninety)])
        XCTAssertEqual(Orientation.operations(for: 8), [.rotate(.twoSeventy)])
        XCTAssertEqual(Orientation.operations(for: 3), [.rotate(.oneEighty)])
        XCTAssertEqual(Orientation.operations(for: 2), [.flip(.horizontal)])
        XCTAssertEqual(Orientation.operations(for: 99), [], "a corrupt tag turns nothing")
        XCTAssertTrue(Orientation.swapsAxes(6))
        XCTAssertFalse(Orientation.swapsAxes(3))
    }

    func testOperationsSurviveJSON() throws {
        let operations: [ImageOperation] = [
            .resize(.fill(width: 400, height: 400, anchor: .smart)),
            .crop(.inset(top: 1, left: 2, bottom: 3, right: 4)),
            .rotate(.oneEighty),
            .pad(.all(8, color: .black)),
            .flatten(.white),
        ]
        let data = try JSONEncoder().encode(operations)
        XCTAssertEqual(try JSONDecoder().decode([ImageOperation].self, from: data), operations)
    }
}
