//
//  Pipeline.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Applying a list of operations to an image, in order.
//
//  Nothing here knows what Vision is. A `.smart` anchor needs to be told
//  where the subject is — ``SubjectDetector`` finds that, asynchronously,
//  before any of this runs — so the whole pipeline stays synchronous, pure,
//  and testable with no model anywhere near it.
//

import CoreGraphics
import Foundation

/// Runs image operations.
public enum Pipeline {

    /// Applies operations to an image.
    ///
    /// - Parameters:
    ///   - operations: The steps, in order.
    ///   - image: The image to start from.
    /// - Returns: The processed image.
    /// - Throws: ``ImageForgeError/requiresAsynchronousProcessing`` if a step
    ///   needs Vision — call ``resolve(_:for:)`` first — and whatever the
    ///   individual steps throw.
    public static func apply(_ operations: [ImageOperation], to image: CGImage) throws -> CGImage {
        var result = image
        for operation in operations {
            guard !operation.needsAnalysis else {
                throw ImageForgeError.requiresAsynchronousProcessing
            }
            result = try apply(operation, to: result)
        }
        return result
    }

    /// Applies one operation.
    ///
    /// - Parameters:
    ///   - operation: The step to apply.
    ///   - image: The image to apply it to.
    /// - Returns: The processed image.
    static func apply(_ operation: ImageOperation, to image: CGImage) throws -> CGImage {
        switch operation {
        case .resize(let spec):
            let plan = Geometry.plan(spec, source: image.pixelSize)
            let scaled = try Renderer.scale(image, to: plan.scaledSize)
            guard let crop = plan.cropRect else { return scaled }
            return try Renderer.crop(scaled, to: crop)

        case .crop(.subject):
            // Needs a detector; `resolve` turns this into a rectangle first.
            throw ImageForgeError.requiresAsynchronousProcessing

        case .crop(.trimTransparent(let tolerance)):
            guard let rect = try AlphaTrim.contentRect(of: image, tolerance: tolerance) else {
                throw ImageForgeError.emptyResult("trimming a fully transparent image")
            }
            return try Renderer.crop(image, to: rect)

        case .crop(let spec):
            return try Renderer.crop(image, to: Geometry.cropRect(for: spec, in: image.pixelSize))

        case .rotate(let angle):
            return try Renderer.rotate(image, by: angle)

        case .rotateFree(let degrees, let background, let cropToFit):
            let turned = try Renderer.rotate(image, byDegrees: degrees, background: background)
            guard cropToFit else { return turned }
            let keep = Geometry.largestInscribedSize(in: image.pixelSize, rotatedBy: degrees)
            let origin = Geometry.anchoredOrigin(inner: keep, outer: turned.pixelSize, anchor: .center)
            return try Renderer.crop(turned, to: CGRect(origin: origin, size: keep))

        case .straighten:
            // Needs the horizon, which needs Vision; `resolve` turns this
            // into a plain `.rotateFree` before the pipeline ever sees it.
            throw ImageForgeError.requiresAsynchronousProcessing

        case .flip(let axis):
            return try Renderer.flip(image, axis)

        case .pad(let spec):
            return try Renderer.pad(image, spec)

        case .flatten(let color):
            return try Renderer.flatten(image, onto: color)

        case .grade(let grade):
            return try Renderer.grade(image, grade)

        case .bakeOrientation:
            // The decoder applies orientation on the way in, so by the time
            // an image reaches the pipeline it is already upright.
            return image
        }
    }

    /// Replaces every step that needs Vision with the plain rectangle Vision
    /// chose, so the result can be run synchronously — and reported.
    ///
    /// A `.fill` resize with a `.smart` anchor becomes an exact scale
    /// followed by an explicit crop, which is what it always meant.
    ///
    /// - Parameters:
    ///   - operations: The steps as the caller wrote them.
    ///   - image: The image they will be applied to.
    ///   - subject: What the picture is about, from ``SubjectDetector``.
    ///     Nil centres instead, which is what a picture with no subject in
    ///     it should do.
    ///   - horizonAngle: How far the horizon is from level, in degrees, from
    ///     ``Detectors/horizonAngle(in:)``. Nil leaves the picture alone.
    /// - Returns: The same steps with nothing left that needs analysis.
    /// - Throws: Whatever the geometry throws.
    public static func resolve(_ operations: [ImageOperation], for image: CGImage,
                               subject: Subject? = nil,
                               horizonAngle: Double? = nil) throws -> [ImageOperation] {
        guard operations.contains(where: { $0.needsAnalysis || $0.expandsToCrop }) else {
            return operations
        }

        var resolved: [ImageOperation] = []
        var size = image.pixelSize
        let center = subject?.center

        for operation in operations {
            guard operation.needsAnalysis || operation.expandsToCrop else {
                resolved.append(operation)
                size = try sizeAfter(operation, from: size, image: image)
                continue
            }

            switch operation {
            case .straighten(let maximum, let minimum, let cropToFit):
                // No horizon, too small to be worth resampling, or too large
                // to be a tilted camera rather than a misread: leave it alone.
                guard let horizonAngle, abs(horizonAngle) >= minimum,
                      abs(horizonAngle) <= maximum else { break }
                resolved.append(.rotateFree(degrees: -horizonAngle, background: .clear,
                                            cropToFit: cropToFit))
                size = cropToFit
                    ? Geometry.largestInscribedSize(in: size, rotatedBy: horizonAngle)
                    : Geometry.rotatedBounds(of: size, degrees: horizonAngle)

            case .crop(.subject(let padding)):
                // Nothing found means no crop at all: cropping to a guess is
                // worse than leaving the picture whole.
                guard let subject else { break }
                let scaled = scale(subject.rect, of: image, into: size)
                let margin = CGSize(width: scaled.width * padding, height: scaled.height * padding)
                let padded = scaled.insetBy(dx: -margin.width, dy: -margin.height)
                    .intersection(CGRect(origin: .zero, size: size))
                guard padded.width >= 1, padded.height >= 1 else { break }
                resolved.append(.crop(.rect(x: Int(padded.minX), y: Int(padded.minY),
                                            width: Int(padded.width), height: Int(padded.height))))
                size = padded.size

            case .crop(let spec):
                let rect = try Geometry.cropRect(for: spec, in: size,
                                                 salientCenter: scale(center, of: image, into: size))
                resolved.append(.crop(.rect(x: Int(rect.minX), y: Int(rect.minY),
                                            width: Int(rect.width), height: Int(rect.height))))
                size = rect.size

            case .resize(let spec):
                let plan = Geometry.plan(spec, source: size)
                resolved.append(.resize(ResizeSpec(width: Int(plan.scaledSize.width),
                                                   height: Int(plan.scaledSize.height),
                                                   mode: .exact)))
                size = plan.scaledSize
                guard let keep = plan.cropRect else { break }
                // The subject's position in the *scaled* image, not the original.
                let origin = Geometry.anchoredOrigin(inner: keep.size, outer: plan.scaledSize,
                                                     anchor: spec.anchor,
                                                     salientCenter: scale(center, of: image,
                                                                          into: plan.scaledSize))
                resolved.append(.crop(.rect(x: Int(origin.x), y: Int(origin.y),
                                            width: Int(keep.width), height: Int(keep.height))))
                size = keep.size

            default:
                resolved.append(operation)
            }
        }
        return resolved
    }

    /// Moves a point found on the original image into the coordinates of a
    /// scaled one. Nil in, nil out — a picture with no subject stays that way.
    ///
    /// - Parameters:
    ///   - point: The point on the original image, or nil.
    ///   - image: The image the point was found on.
    ///   - size: The size to scale the point into.
    /// - Returns: The point in the new coordinates.
    static func scale(_ point: CGPoint?, of image: CGImage, into size: CGSize) -> CGPoint? {
        guard let point, image.width > 0, image.height > 0 else { return nil }
        return CGPoint(x: point.x * size.width / CGFloat(image.width),
                       y: point.y * size.height / CGFloat(image.height))
    }

    /// Moves a rectangle found on the original image into the coordinates of
    /// a scaled one.
    ///
    /// - Parameters:
    ///   - rect: The rectangle on the original image.
    ///   - image: The image it was found on.
    ///   - size: The size to scale it into.
    /// - Returns: The rectangle in the new coordinates.
    static func scale(_ rect: CGRect, of image: CGImage, into size: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0 else { return rect }
        let x = size.width / CGFloat(image.width), y = size.height / CGFloat(image.height)
        return CGRect(x: rect.minX * x, y: rect.minY * y,
                      width: rect.width * x, height: rect.height * y)
    }

    /// The size an operation leaves behind, without doing the work.
    ///
    /// Used while resolving, to keep track of what the next step will be
    /// measured against. Steps whose size depends on the pixels — trimming
    /// transparency — leave the size alone, which is why they are resolved
    /// last rather than predicted.
    ///
    /// - Parameters:
    ///   - operation: The step.
    ///   - size: The size going in.
    ///   - image: The image, for steps that need its alpha.
    /// - Returns: The size coming out.
    static func sizeAfter(_ operation: ImageOperation, from size: CGSize,
                          image: CGImage) throws -> CGSize {
        switch operation {
        case .resize(let spec):
            let plan = Geometry.plan(spec, source: size)
            return plan.cropRect?.size ?? plan.scaledSize
        case .crop(.trimTransparent):
            return size
        case .crop(let spec):
            return try Geometry.cropRect(for: spec, in: size).size
        case .rotate(let angle):
            return angle.swapsAxes ? CGSize(width: size.height, height: size.width) : size
        case .rotateFree(let degrees, _, let cropToFit):
            return cropToFit
                ? Geometry.largestInscribedSize(in: size, rotatedBy: degrees)
                : Geometry.rotatedBounds(of: size, degrees: degrees)
        case .straighten:
            return size
        case .pad(let spec):
            return CGSize(width: size.width + CGFloat(spec.horizontal),
                          height: size.height + CGFloat(spec.vertical))
        case .flip, .flatten, .grade, .bakeOrientation:
            return size
        }
    }
}
