//
//  RendererTests.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Which pixel ends up where. Rotation direction and pad offsets are the
//  two places a coordinate-system mistake hides in plain sight — the image
//  is the right size and the wrong way round — so both are asserted on
//  images small enough to name every pixel.
//

import CoreGraphics
import XCTest
@testable import ImageForge

final class RendererTests: XCTestCase {

    /// Two pixels side by side: red on the left, blue on the right.
    let sideBySide = TestImages.make([[.red, .blue]])

    func testRotatingNinetyDegreesTurnsClockwise() throws {
        let turned = try Renderer.rotate(sideBySide, by: .ninety)
        XCTAssertEqual(turned.width, 1)
        XCTAssertEqual(turned.height, 2)
        // Clockwise: the left-hand pixel goes to the top.
        XCTAssertTrue(TestImages.pixel(turned, x: 0, y: 0).isClose(to: .red),
                      "the left pixel should be on top after a clockwise quarter turn")
        XCTAssertTrue(TestImages.pixel(turned, x: 0, y: 1).isClose(to: .blue))
    }

    func testRotatingThreeQuartersTurnsTheOtherWay() throws {
        let turned = try Renderer.rotate(sideBySide, by: .twoSeventy)
        XCTAssertTrue(TestImages.pixel(turned, x: 0, y: 0).isClose(to: .blue))
        XCTAssertTrue(TestImages.pixel(turned, x: 0, y: 1).isClose(to: .red))
    }

    func testRotatingOneEightyKeepsTheShape() throws {
        let turned = try Renderer.rotate(sideBySide, by: .oneEighty)
        XCTAssertEqual(turned.width, 2)
        XCTAssertEqual(turned.height, 1)
        XCTAssertTrue(TestImages.pixel(turned, x: 0, y: 0).isClose(to: .blue))
    }

    func testHorizontalFlipSwapsLeftAndRight() throws {
        let flipped = try Renderer.flip(sideBySide, .horizontal)
        XCTAssertTrue(TestImages.pixel(flipped, x: 0, y: 0).isClose(to: .blue))
        XCTAssertTrue(TestImages.pixel(flipped, x: 1, y: 0).isClose(to: .red))
    }

    func testVerticalFlipSwapsTopAndBottom() throws {
        let stacked = TestImages.make([[.red], [.blue]])
        let flipped = try Renderer.flip(stacked, .vertical)
        XCTAssertTrue(TestImages.pixel(flipped, x: 0, y: 0).isClose(to: .blue))
        XCTAssertTrue(TestImages.pixel(flipped, x: 0, y: 1).isClose(to: .red))
    }

    func testCropUsesTopLeftOrigin() throws {
        let grid = TestImages.make([[.red, .green], [.blue, .white]])
        let topRight = try Renderer.crop(grid, to: CGRect(x: 1, y: 0, width: 1, height: 1))
        XCTAssertTrue(TestImages.pixel(topRight, x: 0, y: 0).isClose(to: .green),
                      "x:1 y:0 is the top right, not the bottom right")
    }

    func testPadPutsTheImageWhereTheEdgesSay() throws {
        let one = TestImages.solid(.red, width: 1, height: 1)
        let padded = try Renderer.pad(one, PadSpec(top: 2, left: 1, bottom: 0, right: 0,
                                                   color: .black))
        XCTAssertEqual(padded.width, 2)
        XCTAssertEqual(padded.height, 3)
        XCTAssertTrue(TestImages.pixel(padded, x: 1, y: 2).isClose(to: .red),
                      "two rows above and one column left puts the pixel at 1,2")
        XCTAssertTrue(TestImages.pixel(padded, x: 0, y: 0).isClose(to: .black))
    }

    func testFlattenPutsAColourBehindTransparency() throws {
        let clear = TestImages.solid(.clear, width: 2, height: 2)
        let flattened = try Renderer.flatten(clear, onto: .white)
        XCTAssertFalse(flattened.hasAlphaChannel)
        XCTAssertTrue(TestImages.pixel(flattened, x: 0, y: 0).isClose(to: .white))
    }

    func testScalingKeepsTheColours() throws {
        let scaled = try Renderer.scale(TestImages.solid(.red, width: 4, height: 4),
                                        to: CGSize(width: 2, height: 2))
        XCTAssertEqual(scaled.width, 2)
        XCTAssertTrue(TestImages.pixel(scaled, x: 0, y: 0).isClose(to: .red))
    }

    func testScalingToTheSameSizeReturnsTheSameImage() throws {
        let image = TestImages.solid(.red, width: 4, height: 4)
        XCTAssertTrue(try Renderer.scale(image, to: CGSize(width: 4, height: 4)) === image)
    }

    func testGreyscaleConversionDropsColour() throws {
        let grey = try Renderer.convert(TestImages.solid(.red, width: 2, height: 2), to: .gray)
        let pixel = TestImages.pixel(grey, x: 0, y: 0)
        XCTAssertEqual(pixel.r, pixel.g)
        XCTAssertEqual(pixel.g, pixel.b)
    }
}
