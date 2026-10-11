//
//  ComposeTests.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Compositing, measured: every effect is checked in pixels against the
//  number it was asked for, on synthetic layers whose edges are known.
//

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import XCTest
@testable import ImageForge

final class ComposeTests: XCTestCase {

    // MARK: - Helpers

    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    static let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!

    /// An image read back as premultiplied float RGBA, top row first.
    struct Floats {
        let width: Int, height: Int
        let values: [Float]
        func at(_ x: Int, _ y: Int) -> (r: Float, g: Float, b: Float, a: Float) {
            let i = (y * width + x) * 4
            return (values[i], values[i + 1], values[i + 2], values[i + 3])
        }
        func alpha(_ x: Int, _ y: Int) -> Float { at(x, y).a }
    }

    static func floats(_ image: CGImage, in space: CGColorSpace = srgb) -> Floats {
        let width = image.width, height = image.height
        var values = [Float](repeating: 0, count: width * height * 4)
        let context = CIContext(options: [.workingColorSpace: linear])
        // render(toBitmap:) writes the top row first, as a bitmap context does.
        context.render(CIImage(cgImage: image), toBitmap: &values, rowBytes: width * 16,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .RGBAf, colorSpace: space)
        return Floats(width: width, height: height, values: values)
    }

    /// An opaque square on transparent padding — a hard-edged cut-out.
    static func square(_ side: Int, padding: Int = 0, color: CGColor = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)) -> CGImage {
        let total = side + 2 * padding
        let context = CGContext(data: nil, width: total, height: total, bitsPerComponent: 8, bytesPerRow: 0,
                                space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color)
        context.fill(CGRect(x: padding, y: padding, width: side, height: side))
        return context.makeImage()!
    }

    /// A white disc whose alpha falls from 1 to 0 over its outer half — a
    /// soft edge like a cut-out's.
    static func softDisc(_ side: Int) -> CGImage {
        let r = CGFloat(side) / 2
        let gradient = CIFilter.radialGradient()
        gradient.center = CGPoint(x: r, y: r)
        gradient.radius0 = Float(r / 2)
        gradient.radius1 = Float(r)
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        gradient.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
        let image = gradient.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        return CIContext().createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: srgb)!
    }

    /// The first x along a row, from `start`, where alpha falls below `level`.
    static func crossing(_ f: Floats, row: Int, from start: Int, below level: Float) -> Int? {
        (start..<f.width).first { f.alpha($0, row) < level }
    }

    // MARK: - Geometry

    func testSizesAndAnchors() {
        let canvas = CGSize(width: 1200, height: 1200)
        XCTAssertEqual(LayerGeometry.drawnSize(of: CGSize(width: 300, height: 600), as: .fit(0.8), canvas: canvas),
                       CGSize(width: 480, height: 960))
        XCTAssertEqual(LayerGeometry.drawnSize(of: CGSize(width: 300, height: 600), as: .width(150), canvas: nil),
                       CGSize(width: 150, height: 300))
        XCTAssertEqual(LayerGeometry.drawnSize(of: CGSize(width: 300, height: 600), as: .fit(0.5), canvas: nil),
                       CGSize(width: 300, height: 600), "fit with no canvas yet draws at the layer's own size")

        let drawn = CGSize(width: 100, height: 50)
        let corner = LayerPlacement(anchor: .bottomRight, inset: .pixels(24))
        XCTAssertEqual(LayerGeometry.origin(of: drawn, placement: corner, canvas: canvas), CGPoint(x: 1076, y: 1126))
        let percent = LayerPlacement(anchor: .topLeft, inset: .percent(5))
        XCTAssertEqual(LayerGeometry.origin(of: drawn, placement: percent, canvas: canvas), CGPoint(x: 60, y: 60))
        let centred = LayerPlacement(anchor: .bottom, inset: .pixels(30))
        XCTAssertEqual(LayerGeometry.origin(of: drawn, placement: centred, canvas: canvas), CGPoint(x: 550, y: 1120),
                       "the inset applies only to the pinned edge")
        let explicit = LayerPlacement(position: (.percent(10), .pixels(7.4)))
        XCTAssertEqual(LayerGeometry.origin(of: drawn, placement: explicit, canvas: canvas), CGPoint(x: 120, y: 7))

        let reach = LayerGeometry.reach(of: CGRect(x: 0, y: 0, width: 100, height: 100),
                                        effects: LayerEffects(stroke: LayerStroke(width: 4),
                                                              shadow: DropShadow(offsetX: 10, offsetY: 20, blur: 30)))
        XCTAssertEqual(reach, CGRect(x: -20, y: -10, width: 160, height: 160),
                       "the blurred shadow reaches 140 across and 150 down from -20, -10")
    }

    // MARK: - Placement, in pixels

    func testAnchorAndInsetLandWithinAPixel() throws {
        let layer = CompositeLayer(image: Self.square(10),
                                   style: LayerStyle(placement: LayerPlacement(anchor: .bottomRight, inset: .pixels(7))))
        let out = try ImageForge.compose(Composition(size: CGSize(width: 100, height: 80), layers: [layer]))
        let f = Self.floats(out)
        var xs: [Int] = [], ys: [Int] = []
        for y in 0..<80 { for x in 0..<100 where f.alpha(x, y) > 0.5 { xs.append(x); ys.append(y) } }
        XCTAssertEqual(xs.min(), 83); XCTAssertEqual(xs.max(), 92)
        XCTAssertEqual(ys.min(), 63); XCTAssertEqual(ys.max(), 72)
    }

    // MARK: - Effects, measured

    func testStrokeWidthIsMeasuredAtTheEdge() throws {
        let gray = ForgeColor(hex: "#808080")!
        let layer = CompositeLayer(image: Self.square(40), style: LayerStyle(
            effects: LayerEffects(stroke: LayerStroke(width: 6, color: gray))))
        let out = try ImageForge.compose(Composition(size: CGSize(width: 120, height: 120), layers: [layer]))
        let f = Self.floats(out)
        let row = 60
        let covered = (0..<120).filter { f.alpha($0, row) >= 0.5 }
        XCTAssertEqual(covered.count, 52, "40 px square + 6 px each side")
        // The outline is the grey asked for in sRGB — 0.5 there, not 0.5 linear (0.735).
        XCTAssertEqual(f.at(36, row).r, 0.502, accuracy: 0.004)
        // The layer's own pixels are never covered by its outline.
        XCTAssertEqual(f.at(60, row).r, 1, accuracy: 0.002)
        XCTAssertEqual(f.at(60, row).g, 0, accuracy: 0.002)
    }

    func testShadowOffsetAndBlurAreMeasured() throws {
        // Cast well clear of the layer so every edge of the shadow is visible,
        // from a square large enough (12σ) that its far edges do not dim the near.
        let layer = CompositeLayer(image: Self.square(120), style: LayerStyle(
            placement: LayerPlacement(anchor: .left, inset: .pixels(20)),
            effects: LayerEffects(shadow: DropShadow(offsetX: 300, offsetY: 14, blur: 30, opacity: 1))))
        let out = try ImageForge.compose(Composition(size: CGSize(width: 600, height: 320), layers: [layer]))
        let f = Self.floats(out)
        // The square spans x 20..<140, y 100..<220; its shadow x 320..<440,
        // y 114..<234. A blurred hard edge sits at half alpha where it was.
        let row = 174
        let left = try XCTUnwrap((150..<600).first { f.alpha($0, row) >= 0.5 })
        let right = try XCTUnwrap(Self.crossing(f, row: row, from: 380, below: 0.5))
        let bottom = try XCTUnwrap((174..<320).first { f.alpha(380, $0) < 0.5 })
        XCTAssertEqual(left, 320, accuracy: 1, "offsetX")
        XCTAssertEqual(right, 440, accuracy: 1, "offsetX keeps the width")
        XCTAssertEqual(bottom, 234, accuracy: 1, "offsetY")
        // σ = blur / 3 = 10; a Gaussian edge falls from 90% to 10% over 2.563σ.
        let ninety = try XCTUnwrap(Self.crossing(f, row: row, from: 380, below: 0.9))
        let ten = try XCTUnwrap(Self.crossing(f, row: row, from: 380, below: 0.1))
        XCTAssertEqual(Double(ten - ninety), 25.6, accuracy: 2, "softening width")
        XCTAssertEqual(f.alpha(380, row), 1, accuracy: 0.01, "full strength inside")
        print("COMPOSE shadow: edges x \(left)…\(right) (want 320…440), bottom \(bottom) (want 234), 90→10% \(ten - ninety) px (want 25.6)")
    }

    func testGlowReachesItsRadiusAndNoFurther() throws {
        let layer = CompositeLayer(image: Self.square(40), style: LayerStyle(
            effects: LayerEffects(glow: OuterGlow(radius: 15, color: .white, opacity: 1))))
        let out = try ImageForge.compose(Composition(size: CGSize(width: 200, height: 200), layers: [layer]))
        let f = Self.floats(out)
        // Edge at x = 120: half strength there, gone by x = 135.
        XCTAssertEqual(f.alpha(120, 100), 0.5, accuracy: 0.05)
        XCTAssertLessThan(f.alpha(135, 100), 0.01)
        XCTAssertEqual(f.alpha(160, 100), 0, "past its reach the canvas is untouched")
        print("COMPOSE glow: alpha at edge \(f.alpha(120, 100)), at radius \(f.alpha(135, 100)), beyond \(f.alpha(160, 100))")
    }

    func testTransparentCanvasStaysTransparentOutsideTheLayers() throws {
        let layer = CompositeLayer(image: Self.square(30), style: LayerStyle(
            effects: LayerEffects(stroke: LayerStroke(width: 4),
                                  shadow: DropShadow(offsetX: 5, offsetY: 5, blur: 12),
                                  glow: OuterGlow(radius: 9))))
        let out = try ImageForge.compose(Composition(size: CGSize(width: 160, height: 160), layers: [layer]))
        XCTAssertTrue(out.hasAlphaChannel)
        let f = Self.floats(out)
        // The effects reach ≤ 22 px past the 65..<95 square.
        for (x, y) in [(0, 0), (159, 0), (0, 159), (159, 159), (20, 80), (140, 80), (80, 20), (80, 140)] {
            let p = f.at(x, y)
            XCTAssertEqual(p.a, 0, "(\(x),\(y)) alpha")
            XCTAssertEqual(p.r + p.g + p.b, 0, "(\(x),\(y)) colour")
        }
    }

    func testSoftEdgesOnWhiteKeepNoDarkFringe() throws {
        // White soft-edged layers on white must be white everywhere: any dip
        // is a fringe from mishandled premultiplied alpha. Drawn at its own
        // size and downsampled, which takes the resampling path too.
        for size in [LayerSize.original, .scale(0.5), .scale(1.7)] {
            let layer = CompositeLayer(image: Self.softDisc(64), style: LayerStyle(placement: LayerPlacement(size: size)))
            let out = try ImageForge.compose(Composition(backdrop: .color(.white),
                                                         size: CGSize(width: 140, height: 140), layers: [layer]))
            let f = Self.floats(out)
            var deviation: Float = 0
            for y in 0..<140 { for x in 0..<140 {
                let p = f.at(x, y)
                deviation = max(deviation, abs(1 - p.r), abs(1 - p.g), abs(1 - p.b))
            } }
            XCTAssertLessThanOrEqual(deviation, 1.0 / 255, "\(size): max deviation from white \(deviation)")
            print("COMPOSE fringe \(size): max deviation from white \(deviation)")
        }
    }

    func testAnOpaqueBackdropGivesAnOpaqueEightBitPicture() throws {
        let out = try ImageForge.compose(Composition(backdrop: .color(.white), size: CGSize(width: 20, height: 20),
                                                     layers: [CompositeLayer(image: Self.square(8))]))
        XCTAssertFalse(out.hasAlphaChannel)
        XCTAssertEqual(out.bitsPerComponent, 8)
    }

    func testValuesAboveOneSurviveAnHDRPath() throws {
        let bright = CIImage(color: CIColor(red: 4, green: 4, blue: 4, alpha: 1, colorSpace: Self.linear)!)
            .cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let layerImage = try XCTUnwrap(CIContext().createCGImage(bright, from: bright.extent,
                                                                 format: .RGBAh, colorSpace: Self.linear))
        let out = try ImageForge.compose(Composition(size: CGSize(width: 32, height: 32),
                                                     layers: [CompositeLayer(image: layerImage)]))
        XCTAssertEqual(out.bitsPerComponent, 16)
        let f = Self.floats(out, in: Self.linear)
        XCTAssertEqual(f.at(16, 16).r, 4, accuracy: 0.01)
        XCTAssertEqual(f.alpha(2, 2), 0)
    }

    func testABackdropImageCoversTheCanvasCentred() throws {
        // 200×100: red on the left half, blue on the right. On a 100×100
        // canvas it is cropped to its middle, so the split lands at x = 50.
        let context = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: Self.srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        let out = try ImageForge.compose(Composition(backdrop: .image(context.makeImage()!),
                                                     size: CGSize(width: 100, height: 100), layers: []))
        let f = Self.floats(out)
        XCTAssertEqual(f.at(45, 50).r, 1, accuracy: 0.01)
        XCTAssertEqual(f.at(55, 50).b, 1, accuracy: 0.01)
    }

    func testWithNoCanvasTheFirstLayerAndItsEffectsSetTheSize() throws {
        let layer = CompositeLayer(image: Self.square(50), style: LayerStyle(
            effects: LayerEffects(stroke: LayerStroke(width: 5), shadow: DropShadow(offsetY: 10, blur: 12))))
        let out = try ImageForge.compose(Composition(layers: [layer]))
        // Stroke 5 each side; the shadow reaches 12 past its own square, which is 10 lower.
        XCTAssertEqual(out.width, 74)
        XCTAssertEqual(out.height, 77, "5 above (stroke) to 72 below (10 offset + 50 + 12 blur)")
        let f = Self.floats(out)
        XCTAssertEqual(f.at(37, 30).r, 1, accuracy: 0.002, "the layer sits where its effects leave room")
    }

    func testCompositionsThatCannotBeDrawnAreRefused() {
        XCTAssertThrowsError(try ImageForge.compose(Composition(layers: [])))
        XCTAssertThrowsError(try ImageForge.compose(Composition(
            size: CGSize(width: 10, height: 10),
            layers: [CompositeLayer(image: Self.square(4), style: LayerStyle(placement: LayerPlacement(anchor: .smart)))])))
        XCTAssertThrowsError(try ImageForge.compose(Composition(size: CGSize(width: 40_000, height: 10), layers: [])))
    }

    func testAStyleRoundTripsThroughJSON() throws {
        let style = LayerStyle(placement: LayerPlacement(anchor: .bottomRight, inset: .percent(3),
                                                         position: nil, size: .fit(0.25)),
                               effects: LayerEffects(stroke: LayerStroke(width: 8),
                                                     shadow: DropShadow(offsetY: 24, blur: 40),
                                                     glow: nil),
                               opacity: 0.8)
        let data = try JSONEncoder().encode(style)
        XCTAssertEqual(try JSONDecoder().decode(LayerStyle.self, from: data), style)
        let placed = LayerPlacement(position: (.pixels(12), .percent(50)))
        XCTAssertEqual(try JSONDecoder().decode(LayerPlacement.self, from: JSONEncoder().encode(placed)), placed)
    }

    func testWritingAJPEGFlattensOntoTheMatte() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("compose-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("out.jpg")
        let bytes = try ImageForge.compose(Composition(size: CGSize(width: 20, height: 20),
                                                       layers: [CompositeLayer(image: Self.square(8))]),
                                           to: url, encode: EncodeSpec(matte: .white))
        XCTAssertGreaterThan(bytes, 0)
        let info = try ImageForge.describe(url)
        XCTAssertEqual(info.format, .jpeg)
        XCTAssertThrowsError(try ImageForge.compose(Composition(size: CGSize(width: 2, height: 2), layers: []), to: url),
                             "an existing file is not replaced unasked")
    }
}
