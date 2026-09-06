//
//  ImageOperation.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  The vocabulary of the pipeline. Every case is data, so a list of these
//  is a recipe that can be written to a file, sent over a wire, logged, or
//  replayed against a folder — and so that a result can report back the
//  same list with its `.smart` anchors resolved to the rectangles Vision
//  actually chose.
//

import CoreGraphics
import Foundation
import VideoGrade

/// One step of an image pipeline.
///
/// Steps are applied in the order given, and order matters: cropping then
/// resizing is not the same picture as resizing then cropping. Nothing here
/// touches colour or tone — that is
/// [VideoGrade](https://github.com/arraypress/swift-video-grade)'s job, and
/// it composes at the same `CGImage` seam.
public enum ImageOperation: Sendable, Codable, Equatable {
    /// Scale to a target box.
    case resize(ResizeSpec)
    /// Keep part of the image.
    case crop(CropSpec)
    /// Turn by a quarter, half or three-quarter turn, clockwise. Lossless.
    case rotate(RotationAngle)
    /// Turn by any angle, clockwise, resampling as it goes.
    ///
    /// An arbitrary turn leaves triangles of empty canvas at the corners.
    /// `cropToFit` cuts them away by keeping the largest rectangle that
    /// fits entirely inside the turned image; without it they are filled
    /// with `background`.
    case rotateFree(degrees: Double, background: ForgeColor, cropToFit: Bool)
    /// Level the picture, using the horizon Vision finds.
    ///
    /// Does nothing when there is no horizon to find — an indoor photograph
    /// usually has none — or when the lean is under `minimumDegrees`, since
    /// resampling a picture that is already level only softens it.
    case straighten(maximumDegrees: Double, minimumDegrees: Double, cropToFit: Bool)
    /// Mirror across an axis.
    case flip(FlipAxis)
    /// Add canvas around the image.
    case pad(PadSpec)
    /// Composite the image onto a solid colour, discarding its alpha.
    /// What a transparent PNG needs before it becomes a JPEG.
    case flatten(ForgeColor)
    /// Apply colour and tone: exposure, contrast, curves, split-toning, a
    /// LUT, a film look — the whole of
    /// [VideoGrade](https://github.com/arraypress/swift-video-grade), which
    /// this library calls rather than reimplements.
    ///
    /// A grade is a `Codable` value, so a recipe carries the entire look —
    /// including the path to a `.cube` LUT — as data.
    case grade(VideoGrade)
    /// Apply the source's EXIF orientation to the pixels and reset the tag,
    /// so the image is upright to software that ignores the tag.
    ///
    /// The pipeline does this for you when the source needs it; the case
    /// exists so a recipe can be explicit.
    case bakeOrientation

    /// Level the picture using the horizon, cropping away the corners.
    ///
    /// - Parameter maximumDegrees: Refuse to turn further than this; a
    ///   horizon read as 40° off is a misread, not a tilted camera.
    /// - Returns: The operation.
    public static func straighten(maximumDegrees: Double = 15) -> ImageOperation {
        .straighten(maximumDegrees: maximumDegrees, minimumDegrees: 0.2, cropToFit: true)
    }

    /// Whether this step needs Vision, and so needs the asynchronous
    /// entry point.
    ///
    /// A `.fill` resize crops to reach its box, so a `.smart` anchor on one
    /// needs analysis just as a smart crop does.
    public var needsAnalysis: Bool {
        switch self {
        case .crop(let spec): return spec.needsAnalysis
        case .resize(let spec): return spec.mode.crops && spec.anchor.needsAnalysis
        case .straighten: return true
        default: return false
        }
    }

    /// Whether this step is a resize that has to crop to reach its box, and
    /// so is really two steps wearing one name.
    ///
    /// Such a step is expanded during resolution — into an exact scale and
    /// an explicit rectangle — so that a report says which pixels were kept
    /// whatever the anchor was, rather than only when Vision chose them.
    public var expandsToCrop: Bool {
        if case .resize(let spec) = self { return spec.mode.crops }
        return false
    }

    /// Whether ImageIO can perform this step on the destination, without a
    /// `CGImage` ever being built — the only steps an HDR gain map can
    /// survive. Only a plain downscale qualifies.
    public var isPassthroughCapable: Bool {
        guard case .resize(let spec) = self else { return false }
        return !spec.allowsUpscaling && spec.scaleFactor == nil
            && (spec.mode == .fit || spec.mode == .longestSide)
    }

    /// A short phrase naming this step, for a log or a table.
    public var summary: String {
        switch self {
        case .resize(let spec):
            if let factor = spec.scaleFactor {
                return "resize to \(Int(factor * 100))%"
            }
            return "resize \(spec.mode.rawValue) \(spec.width)×\(spec.height)"
        case .crop(let spec):
            switch spec {
            case .rect(let x, let y, let w, let h): return "crop \(w)×\(h) at \(x),\(y)"
            case .aspect(let w, let h, let anchor): return "crop \(w):\(h) \(anchor.rawValue)"
            case .inset(let t, let l, let b, let r): return "inset \(t)/\(l)/\(b)/\(r)"
            case .trimTransparent: return "trim transparent edges"
            case .subject(let padding): return "crop to the subject +\(Int(padding * 100))%"
            }
        case .grade(let grade):
            return grade.lutURL.map { "grade with \($0.lastPathComponent)" } ?? "grade"
        case .rotate(let angle): return "rotate \(angle.rawValue)°"
        case .rotateFree(let degrees, _, let crop):
            return String(format: "rotate %.2f°%@", degrees, crop ? " and crop to fit" : "")
        case .straighten: return "straighten"
        case .flip(let axis): return "flip \(axis.rawValue)"
        case .pad(let spec): return "pad \(spec.top)/\(spec.left)/\(spec.bottom)/\(spec.right)"
        case .flatten(let color): return "flatten onto \(color.hex)"
        case .bakeOrientation: return "bake orientation"
        }
    }
}
