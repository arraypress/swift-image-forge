//
//  AnimationKeys.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Each animated format spells "how long is this frame" differently, in its
//  own dictionary, and gets it wrong in its own way: GIF clamps any delay
//  under 0.02s up to 0.1s for the benefit of 1990s browsers, so the
//  unclamped key has to be read first or a fast loop plays at a crawl.
//

import Foundation
import ImageIO

/// The property keys an animated format uses.
public struct AnimationKeys: Sendable {
    /// The per-format dictionary frame timing lives in.
    public let container: String
    /// The frame delay key, as the format would have it played.
    public let delay: String
    /// The frame delay key as authored, before the format's own clamping.
    public let unclampedDelay: String
    /// The loop-count key.
    public let loopCount: String

    /// The keys for a format, or nil when the format holds no animation.
    ///
    /// - Parameter format: The format to look up.
    /// - Returns: Its animation property keys.
    public static func of(_ format: ImageFormat) -> AnimationKeys? {
        switch format {
        case .gif:
            return AnimationKeys(container: kCGImagePropertyGIFDictionary as String,
                                 delay: kCGImagePropertyGIFDelayTime as String,
                                 unclampedDelay: kCGImagePropertyGIFUnclampedDelayTime as String,
                                 loopCount: kCGImagePropertyGIFLoopCount as String)
        case .png:
            return AnimationKeys(container: kCGImagePropertyPNGDictionary as String,
                                 delay: kCGImagePropertyAPNGDelayTime as String,
                                 unclampedDelay: kCGImagePropertyAPNGUnclampedDelayTime as String,
                                 loopCount: kCGImagePropertyAPNGLoopCount as String)
        case .heicSequence:
            return AnimationKeys(container: kCGImagePropertyHEICSDictionary as String,
                                 delay: kCGImagePropertyHEICSDelayTime as String,
                                 unclampedDelay: kCGImagePropertyHEICSUnclampedDelayTime as String,
                                 loopCount: kCGImagePropertyHEICSLoopCount as String)
        default:
            return nil
        }
    }

    /// The delay a frame's properties describe, in seconds.
    ///
    /// The unclamped value wins where there is one — see the note at the top
    /// of this file about GIF's floor.
    ///
    /// - Parameter properties: One frame's property dictionary.
    /// - Returns: The delay in seconds, or nil when the frame states none.
    public func duration(from properties: [String: Any]) -> Double? {
        guard let frame = properties[container] as? [String: Any] else { return nil }
        if let unclamped = frame[unclampedDelay] as? Double, unclamped > 0 { return unclamped }
        if let clamped = frame[delay] as? Double, clamped > 0 { return clamped }
        return nil
    }

    /// The properties dictionary that gives one frame a delay.
    ///
    /// - Parameter duration: How long the frame is shown, in seconds.
    /// - Returns: A dictionary to pass to `CGImageDestinationAddImage`.
    public func frameProperties(duration: Double) -> [String: Any] {
        [container: [delay: duration, unclampedDelay: duration]]
    }

    /// The properties dictionary that sets an animation's loop count.
    ///
    /// - Parameter loops: Times to play; 0 for forever.
    /// - Returns: A dictionary to pass to `CGImageDestinationSetProperties`.
    public func imageProperties(loops: Int) -> [String: Any] {
        [container: [loopCount: loops]]
    }
}
