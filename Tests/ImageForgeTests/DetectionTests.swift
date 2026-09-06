//
//  DetectionTests.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  The detectors, and the thresholds standing between them and a wrong
//  answer. The document floor in particular is measured rather than chosen,
//  and this file is where that measurement is pinned: it fired at 0.20 on a
//  landscape photograph, and at 0.89 and above on a page.
//

import CoreGraphics
import Foundation
import XCTest
import VideoGrade
@testable import ImageForge

final class DetectionTests: XCTestCase {

    // MARK: - Documents

    func testAPageIsRecognisedWellAboveTheFloor() async throws {
        let quad = try await Detectors.document(in: TestImages.pageOnDesk())
        let page = try XCTUnwrap(quad, "a page on a desk should be found")
        XCTAssertGreaterThanOrEqual(page.confidence, Detectors.MinimumConfidence.document)
        XCTAssertGreaterThan(page.confidence, 0.8, "measured at 0.89 and above")
        XCTAssertTrue(page.isUpright(), "an unskewed page should read as upright")
    }

    func testSkewIsMeasuredAsAnAngle() async throws {
        let quad = try await Detectors.document(in: TestImages.pageOnDesk(skew: 9))
        let page = try XCTUnwrap(quad)
        XCTAssertFalse(page.isUpright())
        // The fixture leans anticlockwise on screen; in top-left origin
        // coordinates that reads negative. Magnitude is what matters.
        XCTAssertEqual(abs(page.skewAngle), 9, accuracy: 1.5)
    }

    func testAPhotographWithNoPageIsNotADocument() async throws {
        // The measurement that produced the floor: this request reports a
        // low-confidence "document" on pictures that plainly are not one.
        let quad = try await Detectors.document(in: TestImages.noise(width: 600, height: 900))
        if let quad {
            XCTAssertGreaterThanOrEqual(quad.confidence, Detectors.MinimumConfidence.document,
                                        "anything returned must have cleared the floor")
        }
    }

    func testTheFloorCanBeLoweredDeliberately() async throws {
        // Not a recommendation — a demonstration that the floor is the only
        // thing rejecting these, so a caller who wants the raw answer can
        // have it.
        let image = TestImages.noise(width: 600, height: 900)
        let strict = try await Detectors.document(in: image)
        let loose = try await Detectors.document(in: image, minimumConfidence: 0)
        if strict == nil, let loose {
            XCTAssertLessThan(loose.confidence, Detectors.MinimumConfidence.document)
        }
    }

    // MARK: - The hierarchy

    func testDocumentsAreNotInTheAutomaticPath() {
        XCTAssertFalse(SubjectStrategy.automatic.order.contains(.document),
                       "a detector that can be wrong about the whole subject stays opt-in")
        XCTAssertEqual(SubjectStrategy.automatic.order, [.face, .person, .animal, .object, .attention])
        XCTAssertEqual(SubjectStrategy.documents.order, [.document])
    }

    func testKindsAreRankedByHowMuchTheyCanBeTrusted() {
        XCTAssertLessThan(SubjectKind.face.rank, SubjectKind.person.rank)
        XCTAssertLessThan(SubjectKind.person.rank, SubjectKind.attention.rank)
        XCTAssertTrue(SubjectKind.face.isDefinite)
        XCTAssertTrue(SubjectKind.document.isDefinite)
        XCTAssertFalse(SubjectKind.attention.isDefinite, "attention is a guess and says so")
        XCTAssertFalse(SubjectKind.object.isDefinite,
                       "objectness is a saliency model too — it cannot name what it found")
    }

    func testStrategiesRunOnlyTheDetectorsTheyName() {
        XCTAssertEqual(SubjectStrategy.faces.order, [.face])
        XCTAssertEqual(SubjectStrategy.people.order, [.face, .person])
        XCTAssertEqual(SubjectStrategy.animals.order, [.animal])
    }

    func testAPictureWithNoSubjectGivesNothingRatherThanAGuess() async throws {
        let flat = TestImages.solid(.white, width: 300, height: 300)
        let subject = try await SubjectDetector.subject(of: flat, strategy: .faces)
        XCTAssertNil(subject, "the faces strategy must not fall through to a guess")
    }

    // MARK: - Detections

    func testDetectionsSummariseWhatWasFound() {
        let detections = Detections(
            imageSize: CGSize(width: 100, height: 100),
            faces: [DetectedFace(rect: CGRect(x: 10, y: 10, width: 20, height: 20),
                                 confidence: 0.9, roll: 0, yaw: 0, pitch: 0, quality: 0.8)],
            people: [], animals: [], objects: [], attention: [],
            document: nil, rectangles: [], horizonAngle: 3.4,
            aestheticsScore: 0.5, isUtilityImage: false)

        XCTAssertEqual(detections.summary, "1 face, horizon +3.4°")
        XCTAssertEqual(Detections(imageSize: .zero, faces: [], people: [], animals: [],
                                  objects: [], attention: [], document: nil,
                                  rectangles: [Quadrilateral(topLeft: .zero, topRight: .zero,
                                                             bottomRight: .zero, bottomLeft: .zero,
                                                             confidence: 1)],
                                  horizonAngle: nil, aestheticsScore: nil,
                                  isUtilityImage: nil).summary,
                       "1 rectangle", "one of a thing is not plural")
        XCTAssertEqual(detections.subject?.kind, .face)
        XCTAssertFalse(detections.isEmpty)
        XCTAssertTrue(detections.needsStraightening())
        XCTAssertFalse(detections.needsStraightening(threshold: 5))
    }

    func testAnEmptyDetectionSaysSo() {
        let empty = Detections(imageSize: .zero, faces: [], people: [], animals: [],
                               objects: [], attention: [], document: nil, rectangles: [],
                               horizonAngle: nil, aestheticsScore: nil, isUtilityImage: nil)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertNil(empty.subject)
        XCTAssertEqual(empty.summary, "nothing found")
        XCTAssertFalse(empty.needsStraightening())
    }

    func testTheSubjectIsTheMostTrustworthyThingFound() {
        let detections = Detections(
            imageSize: CGSize(width: 100, height: 100), faces: [],
            people: [DetectedPerson(rect: CGRect(x: 0, y: 0, width: 50, height: 90),
                                    confidence: 0.6, isUpperBodyOnly: false)],
            animals: [], objects: [CGRect(x: 0, y: 0, width: 10, height: 10)],
            attention: [CGRect(x: 5, y: 5, width: 10, height: 10)],
            document: nil, rectangles: [], horizonAngle: nil,
            aestheticsScore: nil, isUtilityImage: nil)
        XCTAssertEqual(detections.subject?.kind, .person, "a person beats an object and a guess")
    }

    func testSeveralThingsAreUnionedNotPickedFrom() {
        let left = CGRect(x: 0, y: 0, width: 10, height: 10)
        let right = CGRect(x: 90, y: 0, width: 10, height: 10)
        XCTAssertEqual([left, right].union, CGRect(x: 0, y: 0, width: 100, height: 10),
                       "two people should centre between them, not on one")
        XCTAssertNil([CGRect]().union)
    }

    // MARK: - Quadrilaterals

    func testSkewAngleReadsTheEdges() {
        let level = Quadrilateral(topLeft: CGPoint(x: 0, y: 0), topRight: CGPoint(x: 100, y: 0),
                                  bottomRight: CGPoint(x: 100, y: 50),
                                  bottomLeft: CGPoint(x: 0, y: 50), confidence: 1)
        XCTAssertEqual(level.skewAngle, 0, accuracy: 0.001)
        XCTAssertTrue(level.isUpright())
        XCTAssertEqual(level.boundingBox, CGRect(x: 0, y: 0, width: 100, height: 50))

        // Right edge dropped by 10 over a run of 100: about 5.7°.
        let leaning = Quadrilateral(topLeft: CGPoint(x: 0, y: 0), topRight: CGPoint(x: 100, y: 10),
                                    bottomRight: CGPoint(x: 100, y: 60),
                                    bottomLeft: CGPoint(x: 0, y: 50), confidence: 1)
        XCTAssertEqual(leaning.skewAngle, 5.71, accuracy: 0.05)
        XCTAssertFalse(leaning.isUpright())
        XCTAssertTrue(leaning.isUpright(withinDegrees: 10))
    }
}

//
//  Grading — colour and tone, applied by VideoGrade at the CGImage seam.
//

final class GradeTests: XCTestCase {

    func testANeutralGradeChangesNothing() throws {
        let image = TestImages.solid(.red, width: 8, height: 8)
        let out = try Renderer.grade(image, VideoGrade())
        XCTAssertTrue(out === image, "a neutral grade should not even render")
    }

    func testBrightnessActuallyMovesThePixels() throws {
        let image = TestImages.solid(TestImages.Pixel(r: 100, g: 100, b: 100, a: 255),
                                     width: 8, height: 8)
        var grade = VideoGrade()
        grade.brightness = 0.35
        let out = try Renderer.grade(image, grade)
        let before = TestImages.pixel(image, x: 0, y: 0)
        let after = TestImages.pixel(out, x: 0, y: 0)
        XCTAssertGreaterThan(Int(after.r), Int(before.r) + 5, "brighter means brighter")
    }

    func testSaturationCanBeTakenOut() throws {
        let image = TestImages.solid(.red, width: 8, height: 8)
        var grade = VideoGrade()
        grade.saturation = 0
        let out = try Renderer.grade(image, grade)
        let pixel = TestImages.pixel(out, x: 0, y: 0)
        XCTAssertLessThan(abs(Int(pixel.r) - Int(pixel.g)), 20, "desaturated red is grey")
    }

    func testAGradeRunsInThePipelineAlongsideEverythingElse() throws {
        var grade = VideoGrade()
        grade.contrast = 1.2
        let image = TestImages.noise(width: 40, height: 30)
        let result = try Pipeline.apply([
            .resize(ResizeSpec(width: 20, height: 20)),
            .grade(grade),
            .flip(.horizontal),
        ], to: image)
        XCTAssertEqual(result.pixelSize, CGSize(width: 20, height: 15),
                       "grading does not change the geometry")
    }

    func testARecipeCarriesTheWholeLookAsData() throws {
        // The point of the operation being a value: a recipe file holds the
        // grade, the LUT it points at, and everything else, in one document.
        var grade = VideoGrade()
        grade.exposure = 0.2
        grade.contrast = 1.15
        grade.splitShadowAmount = 0.4
        grade.grain = 0.25
        grade.lutURL = URL(fileURLWithPath: "/looks/kodak.cube")

        let options = ProcessOptions(
            operations: [.resize(.longestSide(2048)), .grade(grade)],
            encode: .format(.heic, quality: 0.85))

        let data = try JSONEncoder().encode(options)
        let back = try JSONDecoder().decode(ProcessOptions.self, from: data)
        XCTAssertEqual(back, options)

        guard case .grade(let decoded) = back.operations[1] else {
            return XCTFail("expected a grade")
        }
        XCTAssertEqual(decoded.exposure, 0.2, accuracy: 0.0001)
        XCTAssertEqual(decoded.lutURL?.lastPathComponent, "kodak.cube",
                       "the LUT travels with the recipe")
    }

    func testAMissingLUTIsRefusedRatherThanIgnored() {
        var grade = VideoGrade()
        grade.lutURL = URL(fileURLWithPath: "/no/such/look.cube")
        let image = TestImages.solid(.red, width: 8, height: 8)
        XCTAssertThrowsError(try Renderer.grade(image, grade),
                             "silently skipping a LUT the caller named is worse than failing")
    }
}
