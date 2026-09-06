//
//  CGImage+ImageForge.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Thin conveniences on `CGImage`. Everything here delegates to `Renderer`
//  or `Geometry`; nothing decides anything on its own.
//

import CoreGraphics
import Foundation

public extension CGImage {

    /// The image's size in pixels.
    var pixelSize: CGSize {
        CGSize(width: width, height: height)
    }

    /// Whether the image carries an alpha channel that means anything.
    ///
    /// `.noneSkipFirst` and `.noneSkipLast` have a fourth byte per pixel but
    /// no transparency in it, which is why this is not simply a check for
    /// four components.
    var hasAlphaChannel: Bool {
        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            return false
        }
    }

    /// Width over height. Zero for a zero-height image.
    var aspectRatio: Double {
        height == 0 ? 0 : Double(width) / Double(height)
    }

    /// The image scaled to fit inside a box, aspect ratio kept.
    ///
    /// - Parameters:
    ///   - width: The box's width in pixels.
    ///   - height: The box's height in pixels.
    ///   - allowsUpscaling: Whether the image may be enlarged.
    /// - Returns: The scaled image.
    func resized(toFit width: Int, height: Int, allowsUpscaling: Bool = false) throws -> CGImage {
        let spec = ResizeSpec(width: width, height: height, mode: .fit,
                              allowsUpscaling: allowsUpscaling)
        let plan = Geometry.plan(spec, source: pixelSize)
        return try Renderer.scale(self, to: plan.scaledSize)
    }

    /// The image with no side longer than `pixels`.
    ///
    /// - Parameters:
    ///   - pixels: The longest side allowed.
    ///   - allowsUpscaling: Whether a smaller image may be enlarged to reach it.
    /// - Returns: The scaled image.
    func resized(longestSide pixels: Int, allowsUpscaling: Bool = false) throws -> CGImage {
        let plan = Geometry.plan(.longestSide(pixels, allowsUpscaling: allowsUpscaling),
                                 source: pixelSize)
        return try Renderer.scale(self, to: plan.scaledSize)
    }

    /// The image cropped to a rectangle, in top-left origin pixels.
    ///
    /// - Parameter rect: The rectangle to keep.
    /// - Returns: The cropped image.
    func cropped(to rect: CGRect) throws -> CGImage {
        try Renderer.crop(self, to: rect)
    }

    /// The image turned clockwise.
    ///
    /// - Parameter angle: How far, clockwise.
    /// - Returns: The turned image.
    func rotated(by angle: RotationAngle) throws -> CGImage {
        try Renderer.rotate(self, by: angle)
    }

    /// The image mirrored across an axis.
    ///
    /// - Parameter axis: Which way to mirror.
    /// - Returns: The mirrored image.
    func flipped(_ axis: FlipAxis) throws -> CGImage {
        try Renderer.flip(self, axis)
    }

    /// The image composited onto a solid colour, with no alpha left.
    ///
    /// - Parameter color: The colour behind it.
    /// - Returns: An opaque image.
    func flattened(onto color: ForgeColor) throws -> CGImage {
        try Renderer.flatten(self, onto: color)
    }

    /// The image with a list of operations applied in order.
    ///
    /// - Parameter operations: The steps to apply.
    /// - Returns: The processed image.
    /// - Throws: ``ImageForgeError/requiresAsynchronousProcessing`` if any
    ///   step needs Vision.
    func applying(_ operations: [ImageOperation]) throws -> CGImage {
        try Pipeline.apply(operations, to: self)
    }
}
