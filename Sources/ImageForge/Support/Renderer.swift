//
//  Renderer.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Every operation that has to touch pixels, in one place. Core Graphics
//  bitmap contexts are bottom-left origin while images are top-left; the
//  conversions live here and nowhere else, so the rest of the library can
//  think in the coordinates a person reads off a screenshot.
//

import CoreGraphics
import CoreImage
import Foundation
import VideoGrade

/// Pixel work: scaling, turning, mirroring, padding and flattening.
public enum Renderer {

    /// Scales an image to an exact pixel size.
    ///
    /// - Parameters:
    ///   - image: The image to scale.
    ///   - size: The size to scale to, in pixels.
    /// - Returns: The scaled image.
    /// - Throws: ``ImageForgeError/emptyResult(_:)`` if a context cannot be made.
    public static func scale(_ image: CGImage, to size: CGSize) throws -> CGImage {
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        if width == image.width && height == image.height { return image }

        let context = try makeContext(width: width, height: height, like: image)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return try finish(context, step: "a resize to \(width)×\(height)")
    }

    /// Takes a rectangle out of an image.
    ///
    /// - Parameters:
    ///   - image: The image to crop.
    ///   - rect: The rectangle to keep, in top-left origin pixels.
    /// - Returns: The cropped image.
    /// - Throws: ``ImageForgeError/cropOutOfBounds(requested:imageSize:)``.
    public static func crop(_ image: CGImage, to rect: CGRect) throws -> CGImage {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let integral = rect.integral
        guard bounds.contains(integral), integral.width >= 1, integral.height >= 1,
              let cropped = image.cropping(to: integral) else {
            throw ImageForgeError.cropOutOfBounds(requested: rect, imageSize: bounds.size)
        }
        return cropped
    }

    /// Turns an image clockwise.
    ///
    /// - Parameters:
    ///   - image: The image to turn.
    ///   - angle: How far, clockwise.
    /// - Returns: The turned image, with width and height swapped for a
    ///   quarter or three-quarter turn.
    public static func rotate(_ image: CGImage, by angle: RotationAngle) throws -> CGImage {
        let width = angle.swapsAxes ? image.height : image.width
        let height = angle.swapsAxes ? image.width : image.height

        let context = try makeContext(width: width, height: height, like: image)
        context.interpolationQuality = .high
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        // The context is bottom-left origin, so a positive angle turns the
        // picture anticlockwise. Negate to make `angle` mean what it says.
        context.rotate(by: -angle.radians)
        context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2,
                                       y: -CGFloat(image.height) / 2,
                                       width: CGFloat(image.width),
                                       height: CGFloat(image.height)))
        return try finish(context, step: "a rotation by \(angle.rawValue)°")
    }

    /// Turns an image by any angle, clockwise.
    ///
    /// The canvas grows to hold the turned image, leaving triangles of
    /// empty space at the corners; `background` fills them.
    ///
    /// - Parameters:
    ///   - image: The image to turn.
    ///   - degrees: How far, clockwise.
    ///   - background: What fills the corners.
    /// - Returns: The turned image, larger than it started.
    public static func rotate(_ image: CGImage, byDegrees degrees: Double,
                              background: ForgeColor) throws -> CGImage {
        let bounds = Geometry.rotatedBounds(of: image.pixelSize, degrees: degrees)
        let width = Int(bounds.width), height = Int(bounds.height)

        let context = try makeContext(width: width, height: height, like: image,
                                      forceAlpha: background.alpha < 1)
        context.interpolationQuality = .high
        if background.alpha > 0 {
            context.setFillColor(background.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        // Bottom-left origin, so a positive angle turns anticlockwise on
        // screen; negate to make `degrees` mean clockwise, as everywhere else.
        context.rotate(by: -degrees * .pi / 180)
        context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2,
                                       y: -CGFloat(image.height) / 2,
                                       width: CGFloat(image.width),
                                       height: CGFloat(image.height)))
        return try finish(context, step: String(format: "a rotation by %.2f°", degrees))
    }

    /// Mirrors an image across an axis.
    ///
    /// - Parameters:
    ///   - image: The image to mirror.
    ///   - axis: Which way to mirror it.
    /// - Returns: The mirrored image, the same size.
    public static func flip(_ image: CGImage, _ axis: FlipAxis) throws -> CGImage {
        let context = try makeContext(width: image.width, height: image.height, like: image)
        switch axis {
        case .horizontal:
            context.translateBy(x: CGFloat(image.width), y: 0)
            context.scaleBy(x: -1, y: 1)
        case .vertical:
            context.translateBy(x: 0, y: CGFloat(image.height))
            context.scaleBy(x: 1, y: -1)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return try finish(context, step: "a \(axis.rawValue) flip")
    }

    /// Grows the canvas around an image.
    ///
    /// - Parameters:
    ///   - image: The image to pad.
    ///   - spec: How much to add on each edge, and what colour.
    /// - Returns: The padded image.
    public static func pad(_ image: CGImage, _ spec: PadSpec) throws -> CGImage {
        if spec.isEmpty { return image }
        let width = image.width + spec.horizontal
        let height = image.height + spec.vertical

        let context = try makeContext(width: width, height: height, like: image,
                                      forceAlpha: spec.color.alpha < 1)
        if spec.color.alpha > 0 {
            context.setFillColor(spec.color.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        // `spec.top` counts down from the top; the context counts up from the
        // bottom, so the image's y offset is the *bottom* padding.
        context.draw(image, in: CGRect(x: CGFloat(spec.left), y: CGFloat(spec.bottom),
                                       width: CGFloat(image.width),
                                       height: CGFloat(image.height)))
        return try finish(context, step: "a pad")
    }

    /// Composites an image onto a solid colour, discarding its alpha.
    ///
    /// - Parameters:
    ///   - image: The image to flatten.
    ///   - color: The colour behind it.
    /// - Returns: An opaque image the same size.
    public static func flatten(_ image: CGImage, onto color: ForgeColor) throws -> CGImage {
        let context = try makeContext(width: image.width, height: image.height,
                                      like: image, forceOpaque: true)
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return try finish(context, step: "a flatten")
    }

    /// Redraws an image in a different colour space.
    ///
    /// - Parameters:
    ///   - image: The image to convert.
    ///   - target: The space to convert to. `.unchanged` returns the image.
    /// - Returns: The converted image.
    public static func convert(_ image: CGImage, to target: ColorSpaceTarget) throws -> CGImage {
        guard let space = target.colorSpace else { return image }

        // Greyscale is one component with no alpha and no byte order to
        // state; everything else is 32-bit little-endian, alpha or not.
        let bitmapInfo: UInt32
        if target.isMonochrome {
            bitmapInfo = CGImageAlphaInfo.none.rawValue
        } else {
            let alpha: CGImageAlphaInfo = image.hasAlphaChannel ? .premultipliedFirst : .noneSkipFirst
            bitmapInfo = alpha.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        }

        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: bitmapInfo) else {
            throw ImageForgeError.emptyResult("a conversion to \(target.rawValue)")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return try finish(context, step: "a conversion to \(target.rawValue)")
    }

    /// Applies colour and tone to an image.
    ///
    /// The grade engine works in Core Image and this library works in
    /// `CGImage`, so this is the seam between them: one conversion in, the
    /// engine's own filter chain, one render out.
    ///
    /// - Parameters:
    ///   - image: The image to grade.
    ///   - grade: What to do to it. A neutral grade returns the image untouched.
    /// - Returns: The graded image.
    /// - Throws: ``ImageForgeError/emptyResult(_:)`` when the grade cannot be
    ///   built — a LUT file that is missing or malformed — or the render fails.
    public static func grade(_ image: CGImage, _ grade: VideoGrade) throws -> CGImage {
        guard !grade.isNeutral else { return image }
        let filter: GradeFilter
        do {
            filter = try GradeFilter(grade: grade)
        } catch {
            throw ImageForgeError.emptyResult("a grade: \(error.localizedDescription)")
        }
        let input = CIImage(cgImage: image)
        let output = filter.apply(input)
        // Working space matters: grading in the image's own space keeps a
        // Display P3 photograph from being quietly squeezed into sRGB.
        let context = CIContext(options: [.workingColorSpace: usableColorSpace(for: image)])
        guard let rendered = context.createCGImage(output, from: input.extent) else {
            throw ImageForgeError.emptyResult("rendering a grade")
        }
        return rendered
    }

    // MARK: - Contexts

    /// A bitmap context matching an image's colour space and alpha.
    ///
    /// - Parameters:
    ///   - width: Context width in pixels.
    ///   - height: Context height in pixels.
    ///   - image: The image whose colour space and alpha are copied.
    ///   - forceAlpha: Keep an alpha channel even if the source had none.
    ///   - forceOpaque: Drop the alpha channel even if the source had one.
    /// - Returns: A bitmap context ready to draw into.
    static func makeContext(width: Int, height: Int, like image: CGImage,
                            forceAlpha: Bool = false,
                            forceOpaque: Bool = false) throws -> CGContext {
        let wantsAlpha = forceOpaque ? false : (image.hasAlphaChannel || forceAlpha)
        // A CMYK or indexed source cannot back a bitmap context; sRGB can.
        let space = usableColorSpace(for: image)
        let alpha: CGImageAlphaInfo = wantsAlpha ? .premultipliedFirst : .noneSkipFirst
        let bitmapInfo = alpha.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: bitmapInfo) else {
            throw ImageForgeError.emptyResult("a \(width)×\(height) canvas")
        }
        return context
    }

    /// An RGB colour space a bitmap context will accept, preferring the
    /// image's own.
    static func usableColorSpace(for image: CGImage) -> CGColorSpace {
        let fallback = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let space = image.colorSpace, space.model == .rgb else { return fallback }
        return space
    }

    /// Pulls the image out of a context, or reports which step came up empty.
    static func finish(_ context: CGContext, step: String) throws -> CGImage {
        guard let image = context.makeImage() else {
            throw ImageForgeError.emptyResult(step)
        }
        return image
    }
}
