//
//  ImageFrame.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  One frame of an animation, with the time it is held for. Delays are
//  per-frame rather than a single frame rate because that is how GIF and
//  animated HEIF actually store them, and flattening them to one rate is
//  what makes a re-encoded GIF run at the wrong speed.
//

import CoreGraphics
import Foundation

/// A single frame and how long it stays on screen.
public struct ImageFrame: @unchecked Sendable {
    /// The frame's pixels.
    public let image: CGImage
    /// How long this frame is shown, in seconds.
    public let duration: Double

    /// - Parameters:
    ///   - image: The frame's pixels.
    ///   - duration: How long the frame is shown, in seconds. Clamped to a
    ///     sane floor, since a zero delay means "as fast as possible" to
    ///     some decoders and "one tenth of a second" to others.
    public init(image: CGImage, duration: Double) {
        self.image = image
        self.duration = max(0.01, duration)
    }

    /// The frame's width in pixels.
    public var width: Int { image.width }
    /// The frame's height in pixels.
    public var height: Int { image.height }
}
