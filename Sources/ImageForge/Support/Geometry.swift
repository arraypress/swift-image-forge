//
//  Geometry.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  All the arithmetic, and none of the pixels. Every rectangle the pipeline
//  uses is worked out here, in top-left origin image coordinates, so the
//  sums can be tested against known numbers without decoding anything.
//

import CoreGraphics
import Foundation

/// Resize and crop arithmetic.
public enum Geometry {

    /// What a resize comes to: the size to scale to, and the rectangle to
    /// take out of the scaled image afterwards.
    ///
    /// Only ``ResizeMode/fill`` produces a crop; every other mode scales and
    /// stops.
    public struct ResizePlan: Sendable, Equatable {
        /// The size the image is scaled to.
        public let scaledSize: CGSize
        /// The rectangle to take from the scaled image, in top-left origin
        /// coordinates, or nil when the whole scaled image is the result.
        public let cropRect: CGRect?

        /// - Parameters:
        ///   - scaledSize: The size to scale to.
        ///   - cropRect: The rectangle to keep afterwards, if any.
        public init(scaledSize: CGSize, cropRect: CGRect?) {
            self.scaledSize = scaledSize
            self.cropRect = cropRect
        }
    }

    /// Works out how to reach a target box from a source size.
    ///
    /// - Parameters:
    ///   - spec: The target box and the rules for reaching it.
    ///   - source: The image's current size in pixels.
    ///   - salientCenter: Where the subject is, in top-left origin pixels of
    ///     the *scaled* image, for a `.smart` anchor. Ignored otherwise.
    /// - Returns: The size to scale to and the rectangle to keep.
    public static func plan(_ spec: ResizeSpec, source: CGSize,
                            salientCenter: CGPoint? = nil) -> ResizePlan {
        guard source.width > 0, source.height > 0 else {
            return ResizePlan(scaledSize: CGSize(width: 1, height: 1), cropRect: nil)
        }

        if let factor = spec.scaleFactor {
            return ResizePlan(scaledSize: rounded(CGSize(width: source.width * factor,
                                                         height: source.height * factor)),
                              cropRect: nil)
        }

        let box = CGSize(width: CGFloat(spec.width), height: CGFloat(spec.height))

        if spec.mode == .exact {
            // Exact means exact; `allowsUpscaling` has nothing to say about it.
            return ResizePlan(scaledSize: rounded(box), cropRect: nil)
        }

        var scale = self.scale(for: spec.mode, source: source, box: box)
        if !spec.allowsUpscaling { scale = min(scale, 1) }

        let scaled = rounded(CGSize(width: source.width * scale, height: source.height * scale))
        guard spec.mode.crops else { return ResizePlan(scaledSize: scaled, cropRect: nil) }

        // `.fill` covers the box, then gives back the overflow.
        let keep = CGSize(width: min(box.width, scaled.width),
                          height: min(box.height, scaled.height))
        // An image already the right shape has no overflow to give back, and
        // a crop covering the whole image is noise in a report.
        guard keep.width < scaled.width || keep.height < scaled.height else {
            return ResizePlan(scaledSize: scaled, cropRect: nil)
        }
        let origin = anchoredOrigin(inner: keep, outer: scaled,
                                    anchor: spec.anchor, salientCenter: salientCenter)
        return ResizePlan(scaledSize: scaled,
                          cropRect: CGRect(origin: origin, size: keep))
    }

    /// The scale factor a mode asks for.
    static func scale(for mode: ResizeMode, source: CGSize, box: CGSize) -> CGFloat {
        let byWidth = box.width / source.width
        let byHeight = box.height / source.height
        switch mode {
        case .fit: return min(byWidth, byHeight)
        case .fill: return max(byWidth, byHeight)
        case .width: return byWidth
        case .height: return byHeight
        case .longestSide: return max(box.width, box.height) / max(source.width, source.height)
        case .shortestSide: return min(box.width, box.height) / min(source.width, source.height)
        case .exact: return 1
        }
    }

    /// Where a smaller rectangle sits inside a larger one.
    ///
    /// - Parameters:
    ///   - inner: The rectangle being placed.
    ///   - outer: The space it is placed in.
    ///   - anchor: Which way it is pinned.
    ///   - salientCenter: The point to centre on for a `.smart` anchor, in
    ///     top-left origin pixels. Falls back to the centre when nil.
    /// - Returns: The inner rectangle's origin, top-left.
    public static func anchoredOrigin(inner: CGSize, outer: CGSize, anchor: Anchor,
                                      salientCenter: CGPoint? = nil) -> CGPoint {
        let slackX = max(0, outer.width - inner.width)
        let slackY = max(0, outer.height - inner.height)

        if anchor.needsAnalysis {
            guard let center = salientCenter else {
                return CGPoint(x: (slackX / 2).rounded(), y: (slackY / 2).rounded())
            }
            let x = clamp(center.x - inner.width / 2, 0, slackX)
            let y = clamp(center.y - inner.height / 2, 0, slackY)
            return CGPoint(x: x.rounded(), y: y.rounded())
        }

        let biasX = anchor.horizontalBias ?? 0.5
        let biasY = anchor.verticalBias ?? 0.5
        return CGPoint(x: (slackX * biasX).rounded(), y: (slackY * biasY).rounded())
    }

    /// The rectangle a crop keeps, in top-left origin coordinates.
    ///
    /// - Parameters:
    ///   - spec: What to keep. ``CropSpec/trimTransparent(tolerance:)`` is not
    ///     handled here — it needs the pixels, and lives in ``AlphaTrim``.
    ///   - size: The image's size in pixels.
    ///   - salientCenter: Where the subject is, for a `.smart` anchor.
    /// - Returns: The rectangle to keep.
    /// - Throws: ``ImageForgeError/cropOutOfBounds(requested:imageSize:)`` when
    ///   the rectangle is not inside the image, and
    ///   ``ImageForgeError/emptyResult(_:)`` when it keeps nothing.
    public static func cropRect(for spec: CropSpec, in size: CGSize,
                                salientCenter: CGPoint? = nil) throws -> CGRect {
        let bounds = CGRect(origin: .zero, size: size)
        switch spec {
        case .rect(let x, let y, let width, let height):
            let rect = CGRect(x: CGFloat(x), y: CGFloat(y),
                              width: CGFloat(width), height: CGFloat(height))
            // `CGRect.width` reports the absolute value, so a negative size
            // has to be caught before the rectangle is measured.
            guard width >= 1, height >= 1, bounds.contains(rect) else {
                throw ImageForgeError.cropOutOfBounds(requested: rect, imageSize: size)
            }
            return rect

        case .aspect(let width, let height, let anchor):
            guard width > 0, height > 0 else {
                throw ImageForgeError.emptyResult("a crop with a zero-sided aspect ratio")
            }
            let ratio = CGFloat(width) / CGFloat(height)
            var keep = CGSize(width: size.width, height: (size.width / ratio).rounded(.down))
            if keep.height > size.height {
                keep = CGSize(width: (size.height * ratio).rounded(.down), height: size.height)
            }
            guard keep.width >= 1, keep.height >= 1 else {
                throw ImageForgeError.emptyResult("a crop to \(width):\(height)")
            }
            let origin = anchoredOrigin(inner: keep, outer: size, anchor: anchor,
                                        salientCenter: salientCenter)
            return CGRect(origin: origin, size: keep)

        case .inset(let top, let left, let bottom, let right):
            // Measured as plain numbers first: `CGRect.width` reports the
            // absolute value, so an inset that eats the whole image would
            // otherwise come back as a positive rectangle facing backwards.
            let width = size.width - CGFloat(left + right)
            let height = size.height - CGFloat(top + bottom)
            guard width >= 1, height >= 1 else {
                throw ImageForgeError.emptyResult("an inset of \(top)/\(left)/\(bottom)/\(right)")
            }
            let rect = CGRect(x: CGFloat(left), y: CGFloat(top), width: width, height: height)
            guard bounds.contains(rect) else {
                throw ImageForgeError.cropOutOfBounds(requested: rect, imageSize: size)
            }
            return rect

        case .trimTransparent, .subject:
            // Both need the pixels or a detector; the pipeline resolves them
            // before any rectangle is asked for here.
            return bounds
        }
    }

    /// The size of the largest upright rectangle, of the same proportions
    /// as the original, that fits entirely inside it once it has been
    /// turned by an angle.
    ///
    /// This is what "straighten and crop" needs: turning a picture leaves
    /// four triangles of empty canvas, and the alternative to filling them
    /// is cutting back to the biggest rectangle with none of them in it.
    ///
    /// - Parameters:
    ///   - size: The original size.
    ///   - degrees: How far it is turned. Sign does not matter.
    /// - Returns: The largest size that fits inside, never larger than the
    ///   original and never below one pixel.
    public static func largestInscribedSize(in size: CGSize, rotatedBy degrees: Double) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 1, height: 1) }
        let radians = abs(degrees.truncatingRemainder(dividingBy: 180)) * .pi / 180
        let sinA = abs(sin(radians)), cosA = abs(cos(radians))
        if sinA < 1e-9 { return size }

        let widthIsLonger = size.width >= size.height
        let long = max(size.width, size.height)
        let short = min(size.width, size.height)

        let inner: CGSize
        if short <= 2 * sinA * cosA * long || abs(sinA - cosA) < 1e-9 {
            // Half-constrained: the solution touches only the longer sides.
            let half = 0.5 * short
            inner = widthIsLonger
                ? CGSize(width: half / sinA, height: half / cosA)
                : CGSize(width: half / cosA, height: half / sinA)
        } else {
            let cosDouble = cosA * cosA - sinA * sinA
            inner = CGSize(width: (size.width * cosA - size.height * sinA) / cosDouble,
                           height: (size.height * cosA - size.width * sinA) / cosDouble)
        }
        return CGSize(width: max(1, min(size.width, inner.width.rounded(.down))),
                      height: max(1, min(size.height, inner.height.rounded(.down))))
    }

    /// The size an image grows to once turned by an angle, before any crop.
    ///
    /// - Parameters:
    ///   - size: The original size.
    ///   - degrees: How far it is turned.
    /// - Returns: The bounding size of the turned image.
    public static func rotatedBounds(of size: CGSize, degrees: Double) -> CGSize {
        let radians = degrees * .pi / 180
        let sinA = abs(sin(radians)), cosA = abs(cos(radians))
        return rounded(CGSize(width: size.width * cosA + size.height * sinA,
                              height: size.width * sinA + size.height * cosA))
    }

    /// Rounds a size to whole pixels, never below one.
    static func rounded(_ size: CGSize) -> CGSize {
        CGSize(width: max(1, size.width.rounded()), height: max(1, size.height.rounded()))
    }

    /// Keeps a value inside a range.
    static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), high)
    }
}
