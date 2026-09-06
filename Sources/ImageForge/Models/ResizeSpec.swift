//
//  ResizeSpec.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  A target size, and the rules for reaching it. Kept separate from the
//  arithmetic: `Geometry` turns one of these plus a source size into a
//  concrete rectangle, and can be tested without an image in sight.
//

import CoreGraphics
import Foundation

/// Where an image should end up, dimensionally.
public struct ResizeSpec: Sendable, Codable, Equatable, Hashable {
    /// The target box in pixels. A mode that needs only one dimension —
    /// ``ResizeMode/width``, ``ResizeMode/longestSide`` — ignores the other.
    public var width: Int
    /// The target box's height in pixels.
    public var height: Int
    /// How the box is interpreted.
    public var mode: ResizeMode
    /// Which part survives when ``ResizeMode/fill`` has to crop.
    public var anchor: Anchor
    /// Refuse to make an image bigger than it started. On by default:
    /// enlarging invents detail, and a batch that silently upscales a few
    /// small files produces a folder of soft images nobody asked for.
    public var allowsUpscaling: Bool

    /// - Parameters:
    ///   - width: Target box width in pixels.
    ///   - height: Target box height in pixels.
    ///   - mode: How the box is interpreted. Fits inside it by default.
    ///   - anchor: Which part survives a `.fill` crop. Centre by default.
    ///   - allowsUpscaling: Whether the image may be enlarged. False by default.
    public init(width: Int, height: Int, mode: ResizeMode = .fit,
                anchor: Anchor = .center, allowsUpscaling: Bool = false) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.mode = mode
        self.anchor = anchor
        self.allowsUpscaling = allowsUpscaling
    }

    /// No side longer than `pixels`. The usual way to bound a photo.
    public static func longestSide(_ pixels: Int, allowsUpscaling: Bool = false) -> ResizeSpec {
        ResizeSpec(width: pixels, height: pixels, mode: .longestSide,
                   allowsUpscaling: allowsUpscaling)
    }

    /// This exact width; the height follows.
    public static func width(_ pixels: Int, allowsUpscaling: Bool = false) -> ResizeSpec {
        ResizeSpec(width: pixels, height: pixels, mode: .width,
                   allowsUpscaling: allowsUpscaling)
    }

    /// This exact height; the width follows.
    public static func height(_ pixels: Int, allowsUpscaling: Bool = false) -> ResizeSpec {
        ResizeSpec(width: pixels, height: pixels, mode: .height,
                   allowsUpscaling: allowsUpscaling)
    }

    /// Cover this box exactly, cropping the overflow. The thumbnail case.
    public static func fill(width: Int, height: Int, anchor: Anchor = .center) -> ResizeSpec {
        ResizeSpec(width: width, height: height, mode: .fill,
                   anchor: anchor, allowsUpscaling: true)
    }

    /// A fraction of the source's own size, when the spec came from
    /// ``scaled(by:)``. Resolved against whatever comes in, so it needs no
    /// box and `width`/`height`/`mode` are ignored while it is set.
    public var scaleFactor: Double?

    /// A proportion of whatever comes in. `scaled(by: 0.5)` halves each side.
    public static func scaled(by factor: Double) -> ResizeSpec {
        var spec = ResizeSpec(width: 1, height: 1, mode: .exact, allowsUpscaling: true)
        spec.scaleFactor = max(0.0001, factor)
        return spec
    }
}
