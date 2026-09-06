//
//  GeometryTests.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  The arithmetic, against numbers worked out by hand.
//

import CoreGraphics
import XCTest
@testable import ImageForge

final class GeometryTests: XCTestCase {

    let landscape = CGSize(width: 4000, height: 3000)
    let portrait = CGSize(width: 3000, height: 4000)

    func testFitStaysInsideTheBoxAndKeepsTheRatio() {
        let plan = Geometry.plan(ResizeSpec(width: 1000, height: 1000), source: landscape)
        XCTAssertEqual(plan.scaledSize, CGSize(width: 1000, height: 750))
        XCTAssertNil(plan.cropRect, "fit never crops")
    }

    func testFillCoversTheBoxAndCropsTheOverflow() {
        let plan = Geometry.plan(.fill(width: 1000, height: 1000), source: landscape)
        XCTAssertEqual(plan.scaledSize, CGSize(width: 1333, height: 1000))
        XCTAssertEqual(plan.cropRect, CGRect(x: 167, y: 0, width: 1000, height: 1000))
    }

    func testFillAnchorsToTheEdgeWhenAsked() {
        let left = Geometry.plan(.fill(width: 1000, height: 1000, anchor: .left), source: landscape)
        XCTAssertEqual(left.cropRect?.minX, 0)
        let right = Geometry.plan(.fill(width: 1000, height: 1000, anchor: .right), source: landscape)
        XCTAssertEqual(right.cropRect?.minX, 333)
    }

    func testLongestSideIsOrientationAgnostic() {
        XCTAssertEqual(Geometry.plan(.longestSide(2000), source: landscape).scaledSize,
                       CGSize(width: 2000, height: 1500))
        XCTAssertEqual(Geometry.plan(.longestSide(2000), source: portrait).scaledSize,
                       CGSize(width: 1500, height: 2000))
    }

    func testShortestSideBoundsTheOtherWay() {
        XCTAssertEqual(Geometry.plan(ResizeSpec(width: 1500, height: 1500, mode: .shortestSide),
                                     source: landscape).scaledSize,
                       CGSize(width: 2000, height: 1500))
    }

    func testUpscalingIsRefusedUnlessAskedFor() {
        let small = CGSize(width: 100, height: 100)
        XCTAssertEqual(Geometry.plan(.longestSide(1000), source: small).scaledSize, small,
                       "a small image is left alone rather than blown up")
        XCTAssertEqual(Geometry.plan(.longestSide(1000, allowsUpscaling: true), source: small).scaledSize,
                       CGSize(width: 1000, height: 1000))
    }

    func testExactIgnoresTheAspectRatioAndTheUpscaleRule() {
        let plan = Geometry.plan(ResizeSpec(width: 800, height: 200, mode: .exact),
                                 source: CGSize(width: 100, height: 100))
        XCTAssertEqual(plan.scaledSize, CGSize(width: 800, height: 200))
    }

    func testWidthAndHeightModesFollowTheRatio() {
        XCTAssertEqual(Geometry.plan(.width(2000), source: landscape).scaledSize,
                       CGSize(width: 2000, height: 1500))
        XCTAssertEqual(Geometry.plan(.height(1500), source: landscape).scaledSize,
                       CGSize(width: 2000, height: 1500))
    }

    func testScaledByAFactorNeedsNoBox() {
        XCTAssertEqual(Geometry.plan(.scaled(by: 0.25), source: landscape).scaledSize,
                       CGSize(width: 1000, height: 750))
    }

    func testAnchoredOriginPutsTheSlackWhereTheAnchorSays() {
        let inner = CGSize(width: 100, height: 100)
        let outer = CGSize(width: 300, height: 200)
        XCTAssertEqual(Geometry.anchoredOrigin(inner: inner, outer: outer, anchor: .topLeft),
                       CGPoint(x: 0, y: 0))
        XCTAssertEqual(Geometry.anchoredOrigin(inner: inner, outer: outer, anchor: .center),
                       CGPoint(x: 100, y: 50))
        XCTAssertEqual(Geometry.anchoredOrigin(inner: inner, outer: outer, anchor: .bottomRight),
                       CGPoint(x: 200, y: 100))
    }

    func testSmartAnchorCentresOnTheSubjectAndStaysInBounds() {
        let inner = CGSize(width: 100, height: 100)
        let outer = CGSize(width: 300, height: 300)
        // A subject near the left edge cannot be centred on without leaving
        // the image, so the crop is pushed back to the edge instead.
        let origin = Geometry.anchoredOrigin(inner: inner, outer: outer, anchor: .smart,
                                             salientCenter: CGPoint(x: 10, y: 150))
        XCTAssertEqual(origin, CGPoint(x: 0, y: 100))
    }

    func testSmartAnchorFallsBackToTheCentreWithNoSubject() {
        let origin = Geometry.anchoredOrigin(inner: CGSize(width: 100, height: 100),
                                             outer: CGSize(width: 300, height: 300),
                                             anchor: .smart, salientCenter: nil)
        XCTAssertEqual(origin, CGPoint(x: 100, y: 100))
    }

    func testAspectCropTakesTheLargestRectangleThatFits() throws {
        let rect = try Geometry.cropRect(for: .aspect(width: 1, height: 1, anchor: .center),
                                         in: CGSize(width: 400, height: 300))
        XCTAssertEqual(rect, CGRect(x: 50, y: 0, width: 300, height: 300))
    }

    func testInsetCropTrimsEachEdge() throws {
        let rect = try Geometry.cropRect(for: .inset(top: 10, left: 20, bottom: 30, right: 40),
                                         in: CGSize(width: 200, height: 100))
        XCTAssertEqual(rect, CGRect(x: 20, y: 10, width: 140, height: 60))
    }

    func testCropOutsideTheImageIsRefused() {
        XCTAssertThrowsError(try Geometry.cropRect(for: .rect(x: 90, y: 0, width: 20, height: 20),
                                                   in: CGSize(width: 100, height: 100))) { error in
            guard case ImageForgeError.cropOutOfBounds = error else {
                return XCTFail("expected cropOutOfBounds, got \(error)")
            }
        }
    }

    func testAnInsetThatKeepsNothingIsRefused() {
        XCTAssertThrowsError(try Geometry.cropRect(for: .inset(top: 60, left: 0, bottom: 60, right: 0),
                                                   in: CGSize(width: 100, height: 100)))
    }
}
