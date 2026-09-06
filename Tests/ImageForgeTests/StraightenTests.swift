//
//  StraightenTests.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Turning a picture by an arbitrary angle, and cutting back to the largest
//  rectangle with none of the empty corners in it. The inscribed-rectangle
//  formula is the kind of thing that looks right and is quietly wrong, so
//  it is checked against angles whose answers can be worked out by hand.
//

import CoreGraphics
import XCTest
@testable import ImageForge

final class StraightenTests: XCTestCase {

    // MARK: - The maths

    func testTurningNothingChangesNothing() {
        let size = CGSize(width: 400, height: 300)
        XCTAssertEqual(Geometry.largestInscribedSize(in: size, rotatedBy: 0), size)
        XCTAssertEqual(Geometry.rotatedBounds(of: size, degrees: 0), size)
    }

    func testAQuarterTurnSwapsTheBounds() {
        let bounds = Geometry.rotatedBounds(of: CGSize(width: 400, height: 300), degrees: 90)
        XCTAssertEqual(bounds, CGSize(width: 300, height: 400))
    }

    func testTurningGrowsTheCanvas() {
        // A 100×100 square turned 45° needs 100√2 ≈ 141 on each side.
        let bounds = Geometry.rotatedBounds(of: CGSize(width: 100, height: 100), degrees: 45)
        XCTAssertEqual(bounds.width, 141, accuracy: 1)
        XCTAssertEqual(bounds.height, 141, accuracy: 1)
    }

    func testTheInscribedSquareOfATurnedSquare() {
        // The largest square inside a square turned 45° has side w/√2 ≈ 70.7.
        let inner = Geometry.largestInscribedSize(in: CGSize(width: 100, height: 100), rotatedBy: 45)
        XCTAssertEqual(inner.width, 70, accuracy: 1.5)
        XCTAssertEqual(inner.height, 70, accuracy: 1.5)
    }

    func testTheInscribedSizeNeverExceedsTheOriginal() {
        let size = CGSize(width: 1000, height: 600)
        for degrees in stride(from: -30.0, through: 30.0, by: 2.5) {
            let inner = Geometry.largestInscribedSize(in: size, rotatedBy: degrees)
            XCTAssertLessThanOrEqual(inner.width, size.width, "at \(degrees)°")
            XCTAssertLessThanOrEqual(inner.height, size.height, "at \(degrees)°")
            XCTAssertGreaterThan(inner.width, 0)
            XCTAssertGreaterThan(inner.height, 0)
        }
    }

    func testSmallAnglesBarelyCostAnything() {
        // The whole argument for straightening: a 2° correction gives up a
        // few percent of the frame, not a third of it.
        let size = CGSize(width: 1000, height: 750)
        let inner = Geometry.largestInscribedSize(in: size, rotatedBy: 2)
        XCTAssertGreaterThan(inner.width * inner.height, size.width * size.height * 0.9)
    }

    func testTheSignOfTheAngleDoesNotChangeTheSize() {
        let size = CGSize(width: 800, height: 500)
        XCTAssertEqual(Geometry.largestInscribedSize(in: size, rotatedBy: 7),
                       Geometry.largestInscribedSize(in: size, rotatedBy: -7))
    }

    // MARK: - The pixels

    func testFreeRotationGrowsTheImage() throws {
        let image = TestImages.solid(.red, width: 100, height: 100)
        let turned = try Renderer.rotate(image, byDegrees: 30, background: .black)
        XCTAssertGreaterThan(turned.width, 100)
        XCTAssertGreaterThan(turned.height, 100)
        // The corners are canvas, not picture.
        XCTAssertTrue(TestImages.pixel(turned, x: 1, y: 1).isClose(to: .black))
    }

    func testCroppingToFitLeavesNoEmptyCorners() throws {
        let image = TestImages.solid(.red, width: 200, height: 200)
        let result = try Pipeline.apply(
            [.rotateFree(degrees: 10, background: .black, cropToFit: true)], to: image)

        XCTAssertLessThanOrEqual(result.width, 200)
        for (x, y) in [(0, 0), (result.width - 1, 0), (0, result.height - 1),
                       (result.width - 1, result.height - 1)] {
            XCTAssertTrue(TestImages.pixel(result, x: x, y: y).isClose(to: .red, tolerance: 30),
                          "corner \(x),\(y) should be picture, not canvas")
        }
    }

    // MARK: - Resolution

    let level = TestImages.solid(.red, width: 200, height: 100)

    func testStraightenBecomesARotationTheOtherWay() throws {
        let resolved = try Pipeline.resolve([.straighten()], for: level, horizonAngle: 4)
        XCTAssertEqual(resolved.count, 1)
        guard case .rotateFree(let degrees, _, let cropToFit) = resolved[0] else {
            return XCTFail("expected a free rotation, got \(resolved)")
        }
        // Measured: Vision reports the same sign as a clockwise turn, so
        // levelling means turning back by the negation.
        XCTAssertEqual(degrees, -4, accuracy: 0.001)
        XCTAssertTrue(cropToFit)
    }

    func testNoHorizonMeansNoRotation() throws {
        let resolved = try Pipeline.resolve([.straighten()], for: level, horizonAngle: nil)
        XCTAssertTrue(resolved.isEmpty, "an indoor photograph is left alone")
    }

    func testATinyLeanIsNotWorthResampling() throws {
        let resolved = try Pipeline.resolve([.straighten()], for: level, horizonAngle: 0.05)
        XCTAssertTrue(resolved.isEmpty)
    }

    func testAnAbsurdAngleIsTreatedAsAMisread() throws {
        let resolved = try Pipeline.resolve([.straighten(maximumDegrees: 15)],
                                            for: level, horizonAngle: 40)
        XCTAssertTrue(resolved.isEmpty, "40° is a misread, not a tilted camera")
    }

    func testStraightenRefusesTheSynchronousPath() {
        XCTAssertThrowsError(try Pipeline.apply([.straighten()], to: level)) { error in
            guard case ImageForgeError.requiresAsynchronousProcessing = error else {
                return XCTFail("expected requiresAsynchronousProcessing, got \(error)")
            }
        }
    }

    // MARK: - Cropping to the subject

    func testCroppingToTheSubjectKeepsItAndAMargin() throws {
        let image = TestImages.solid(.red, width: 400, height: 400)
        let subject = Subject(rect: CGRect(x: 100, y: 100, width: 100, height: 100),
                              kind: .face, count: 1)
        let resolved = try Pipeline.resolve([.crop(.subject(padding: 0.2))],
                                            for: image, subject: subject)

        guard case .crop(.rect(let x, let y, let width, let height)) = resolved[0] else {
            return XCTFail("expected a rectangle, got \(resolved)")
        }
        // 20 % of a 100px subject is 20px on each side.
        XCTAssertEqual(x, 80)
        XCTAssertEqual(y, 80)
        XCTAssertEqual(width, 140)
        XCTAssertEqual(height, 140)
    }

    func testTheMarginIsClippedToTheImage() throws {
        let image = TestImages.solid(.red, width: 200, height: 200)
        let subject = Subject(rect: CGRect(x: 0, y: 0, width: 200, height: 200),
                              kind: .person, count: 1)
        let resolved = try Pipeline.resolve([.crop(.subject(padding: 0.5))],
                                            for: image, subject: subject)
        guard case .crop(.rect(let x, let y, let width, let height)) = resolved[0] else {
            return XCTFail("expected a rectangle, got \(resolved)")
        }
        XCTAssertEqual([x, y, width, height], [0, 0, 200, 200])
    }

    func testNoSubjectMeansNoCropRatherThanAGuess() throws {
        let resolved = try Pipeline.resolve([.crop(.subject(padding: 0.1))],
                                            for: level, subject: nil)
        XCTAssertTrue(resolved.isEmpty, "cropping to a guess is worse than not cropping")
    }

    func testSubjectCropRefusesTheSynchronousPath() {
        XCTAssertThrowsError(try Pipeline.apply([.crop(.subject(padding: 0))], to: level))
    }

    // MARK: - Nothing to do

    func testAStraightenWithNoHorizonCopiesRatherThanReEncodes() async throws {
        // The defect this exists to prevent: an indoor photograph has no
        // horizon, so nothing happens — and without the copy path the file is
        // still decoded and re-encoded, losing quality and often growing.
        let directory = TestImages.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("flat.jpg")
        let data = try ImageEncoder.encode(TestImages.noise(width: 400, height: 300),
                                           format: .jpeg, spec: EncodeSpec(format: .jpeg))
        try ImageEncoder.write(data, to: source, overwrites: true)

        let destination = directory.appendingPathComponent("out.jpg")
        let result = try await ImageForge.process(source, to: destination, options: ProcessOptions(
            operations: [.straighten()],
            encode: EncodeSpec(format: .jpeg, quality: 0.2),
            copiesWhenUnchanged: true))

        XCTAssertTrue(result.copiedVerbatim)
        XCTAssertTrue(result.operations.isEmpty)
        XCTAssertEqual(result.bytesAfter, result.bytesBefore, "byte for byte")
        XCTAssertEqual(try Data(contentsOf: destination), data)
    }

    func testTheCopyIsRefusedWhenTheEncodeWouldHaveChangedSomething() {
        let jpeg = ImageInfo(width: 10, height: 10, storedWidth: 10, storedHeight: 10,
                             format: .jpeg, typeIdentifier: "public.jpeg", orientation: 1,
                             hasAlpha: false, bitsPerComponent: 8, colorSpaceName: nil,
                             hasGainMap: false, frameCount: 1, byteCount: 1,
                             hasLocation: false, capturedAt: nil)

        XCTAssertTrue(ImageForge.canCopy(before: jpeg, format: .jpeg, encode: EncodeSpec()))
        XCTAssertFalse(ImageForge.canCopy(before: jpeg, format: .png, encode: EncodeSpec()),
                       "a different container is a change")
        XCTAssertFalse(ImageForge.canCopy(before: jpeg, format: .jpeg,
                                          encode: EncodeSpec(maximumBytes: 100)),
                       "a byte budget is a change")
        XCTAssertFalse(ImageForge.canCopy(before: jpeg, format: .jpeg,
                                          encode: EncodeSpec(colorSpace: .gray)),
                       "a colour conversion is a change")
        XCTAssertFalse(ImageForge.canCopy(before: jpeg, format: .jpeg,
                                          encode: EncodeSpec(metadata: .strip)),
                       "stripping metadata is a change")
    }

    func testACopyIsRefusedWhenThereIsLocationToStrip() {
        let located = ImageInfo(width: 10, height: 10, storedWidth: 10, storedHeight: 10,
                                format: .jpeg, typeIdentifier: "public.jpeg", orientation: 1,
                                hasAlpha: false, bitsPerComponent: 8, colorSpaceName: nil,
                                hasGainMap: false, frameCount: 1, byteCount: 1,
                                hasLocation: true, capturedAt: nil)
        XCTAssertFalse(ImageForge.canCopy(before: located, format: .jpeg,
                                          encode: EncodeSpec(metadata: .stripLocation)),
                       "copying would leak the coordinates the policy exists to remove")
    }

    // MARK: - Recipes

    func testTheNewOperationsSurviveJSON() throws {
        let operations: [ImageOperation] = [
            .straighten(),
            .straighten(maximumDegrees: 5, minimumDegrees: 1, cropToFit: false),
            .rotateFree(degrees: -2.5, background: .black, cropToFit: true),
            .crop(.subject(padding: 0.25)),
        ]
        let data = try JSONEncoder().encode(operations)
        XCTAssertEqual(try JSONDecoder().decode([ImageOperation].self, from: data), operations)
    }
}
