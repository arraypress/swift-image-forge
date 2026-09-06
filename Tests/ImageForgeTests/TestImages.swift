//
//  TestImages.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Synthetic images whose every pixel is known, so a rotation can be
//  asserted rather than eyeballed. Nothing here reads a fixture off disk:
//  a test that depends on a JPEG somebody committed in 2019 fails for
//  reasons that have nothing to do with the code.
//

import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
@testable import ImageForge

enum TestImages {

    /// One pixel, as bytes in RGBA order.
    struct Pixel: Equatable, CustomStringConvertible {
        let r: UInt8, g: UInt8, b: UInt8, a: UInt8

        var description: String { "rgba(\(r),\(g),\(b),\(a))" }

        static let red = Pixel(r: 255, g: 0, b: 0, a: 255)
        static let green = Pixel(r: 0, g: 255, b: 0, a: 255)
        static let blue = Pixel(r: 0, g: 0, b: 255, a: 255)
        static let white = Pixel(r: 255, g: 255, b: 255, a: 255)
        static let black = Pixel(r: 0, g: 0, b: 0, a: 255)
        static let clear = Pixel(r: 0, g: 0, b: 0, a: 0)

        /// Whether two colours are within a tolerance on every channel.
        /// Encoders are allowed to be a shade off; they are not allowed to
        /// put the red pixel where the blue one was.
        func isClose(to other: Pixel, tolerance: Int = 6) -> Bool {
            abs(Int(r) - Int(other.r)) <= tolerance
                && abs(Int(g) - Int(other.g)) <= tolerance
                && abs(Int(b) - Int(other.b)) <= tolerance
                && abs(Int(a) - Int(other.a)) <= tolerance
        }
    }

    /// An image built from a grid of pixels, given row by row from the top.
    static func make(_ rows: [[Pixel]]) -> CGImage {
        let height = rows.count
        let width = rows[0].count
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * height * 4)
        for row in rows {
            for pixel in row {
                // Premultiplied, and every test colour is either solid or
                // fully clear, so the premultiplication is the identity.
                bytes += [pixel.r, pixel.g, pixel.b, pixel.a]
            }
        }

        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8,
                       bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue:
                        CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// A solid block of one colour.
    static func solid(_ pixel: Pixel, width: Int, height: Int) -> CGImage {
        make(Array(repeating: Array(repeating: pixel, count: width), count: height))
    }

    /// Every pixel of an image, row by row from the top.
    static func read(_ image: CGImage) -> [[Pixel]] {
        let width = image.width, height = image.height
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                        | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (0..<height).map { y in
            (0..<width).map { x in
                let offset = y * bytesPerRow + x * 4
                return Pixel(r: bytes[offset], g: bytes[offset + 1],
                             b: bytes[offset + 2], a: bytes[offset + 3])
            }
        }
    }

    /// One pixel of an image, counted from the top left.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> Pixel {
        read(image)[y][x]
    }

    /// A deterministic field of noise — the hard case for a compressor, so
    /// a byte budget has something real to bite on.
    static func noise(width: Int, height: Int, seed: UInt64 = 7919) -> CGImage {
        var state = seed
        func next() -> UInt8 {
            // xorshift64: no dependencies, and the same picture every run.
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return UInt8(truncatingIfNeeded: state >> 24)
        }
        let rows = (0..<height).map { _ in
            (0..<width).map { _ in Pixel(r: next(), g: next(), b: next(), a: 255) }
        }
        return make(rows)
    }

    /// Writes a HEIC carrying a real HDR gain map, so the one claim that
    /// cannot be checked by looking at the picture can be checked at all.
    ///
    /// A gain map is a second, single-channel image stored beside the base
    /// one; it is attached with `CGImageDestinationAddAuxiliaryDataInfo`,
    /// which is the only way to put one in a file from scratch.
    @discardableResult
    static func writeGainMapHEIC(to url: URL, width: Int = 64, height: Int = 64) throws -> URL {
        let base = solid(Pixel(r: 230, g: 100, b: 25, a: 255), width: width, height: height)

        // A horizontal ramp, which is a perfectly good gain map.
        var map = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { map[y * width + x] = UInt8(x * 255 / max(1, width - 1)) }
        }
        let info: [String: Any] = [
            kCGImageAuxiliaryDataInfoData as String: Data(map) as CFData,
            kCGImageAuxiliaryDataInfoDataDescription as String: [
                "PixelFormat": Int(kCVPixelFormatType_OneComponent8),
                "Width": width, "Height": height, "BytesPerRow": width,
            ],
        ]

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, ImageFormat.heic.typeIdentifier as CFString, 1, nil) else {
            throw ImageForgeError.encodingFailed(.heic, reason: "no encoder in the test")
        }
        CGImageDestinationAddImage(destination, base,
                                   [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        CGImageDestinationAddAuxiliaryDataInfo(destination, kCGImageAuxiliaryDataTypeHDRGainMap,
                                               info as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageForgeError.encodingFailed(.heic, reason: "the fixture would not finalise")
        }
        return url
    }

    /// A page photographed on a dark surface, optionally skewed — enough of
    /// a document for Vision to recognise one, built from rectangles so the
    /// test needs no fixture file.
    ///
    /// - Parameter skew: How far to lean the page, in degrees anticlockwise.
    /// - Returns: The image.
    static func pageOnDesk(skew: CGFloat = 0, width: Int = 1200, height: Int = 1600) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue)!
        context.setFillColor(CGColor(red: 0.16, green: 0.13, blue: 0.11, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.saveGState()
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: skew * .pi / 180)
        context.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)

        let page = CGRect(x: CGFloat(width) * 0.125, y: CGFloat(height) * 0.125,
                          width: CGFloat(width) * 0.75, height: CGFloat(height) * 0.75)
        context.setFillColor(CGColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1))
        context.fill(page)

        context.setFillColor(CGColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 1))
        for row in 0..<26 {
            let y = page.maxY - 120 - CGFloat(row) * 42
            guard y > page.minY + 40 else { break }
            context.fill(CGRect(x: page.minX + 90, y: y,
                                width: row % 5 == 4 ? 380 : 720, height: 16))
        }
        context.restoreGState()
        return context.makeImage()!
    }

    /// A directory that cleans itself up.
    static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("image-forge-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
