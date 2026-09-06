//
//  AlphaTrim.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Finding the picture inside the empty space. A cutout, a logo exported
//  from a design tool, a rendered sprite — all arrive padded with
//  transparency that no crop rectangle can predict, because the padding
//  depends on the pixels.
//

import CoreGraphics
import Foundation

/// Finds the part of an image that is not transparent.
public enum AlphaTrim {

    /// The smallest rectangle containing every pixel more opaque than the
    /// tolerance, in top-left origin pixels.
    ///
    /// - Parameters:
    ///   - image: The image to measure.
    ///   - tolerance: Alpha at or below this counts as empty, from 0 to 1.
    ///     Zero means only fully transparent pixels are trimmed.
    /// - Returns: The occupied rectangle, or nil when every pixel is empty.
    /// - Throws: ``ImageForgeError/emptyResult(_:)`` if the pixels cannot be read.
    public static func contentRect(of image: CGImage, tolerance: Double = 0) throws -> CGRect? {
        guard image.hasAlphaChannel else {
            return CGRect(x: 0, y: 0, width: image.width, height: image.height)
        }

        let width = image.width, height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let threshold = UInt8(min(255, max(0, tolerance * 255)))

        // A fixed RGBA layout, so alpha is always the fourth byte whatever
        // the source image happened to be stored as.
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                          space: space, bitmapInfo: bitmapInfo) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw ImageForgeError.emptyResult("reading the alpha channel") }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width where pixels[row + x * 4 + 3] > threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
