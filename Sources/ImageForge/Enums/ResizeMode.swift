//
//  ResizeMode.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  How a target size is interpreted. The distinction that matters is
//  whether the aspect ratio is allowed to change and whether the result is
//  allowed to be cropped to reach the box.
//

import CoreGraphics
import Foundation

/// How to fit an image to a target box.
///
/// Every mode is expressed against a box; which of the box's dimensions are
/// used depends on the mode, and a mode that needs only one dimension
/// ignores the other.
public enum ResizeMode: String, CaseIterable, Sendable, Codable, Hashable {
    /// Largest size that fits *inside* the box, aspect ratio kept.
    /// A 4000×3000 image into a 1000×1000 box becomes 1000×750.
    case fit
    /// Smallest size that *covers* the box, aspect ratio kept, overflow
    /// cropped to the box from the anchor. A 4000×3000 image into a
    /// 1000×1000 box becomes 1000×1000, losing the sides.
    case fill
    /// Exactly the box, aspect ratio ignored. Distorts.
    case exact
    /// The box's width; height follows from the aspect ratio.
    case width
    /// The box's height; width follows from the aspect ratio.
    case height
    /// The box's larger dimension becomes the image's longer side.
    /// The orientation-agnostic way to say "no bigger than 2048".
    case longestSide
    /// The box's smaller dimension becomes the image's shorter side.
    case shortestSide

    /// Whether this mode can leave part of the image outside the box, and so
    /// needs a crop and an anchor to finish.
    public var crops: Bool { self == .fill }
}
