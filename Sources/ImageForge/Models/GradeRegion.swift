//
//  GradeRegion.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Where a grade applies, when not everywhere.
///
/// A recipe keeps the *name* — `.named("sky", …)` — so replaying it finds
/// the sky in each new picture; the mask is resolved when the job runs, by
/// the ``ImageForge/RegionResolver`` the caller passes in (ImageForge itself
/// runs no segmentation model).
public enum GradeRegion: Sendable, Codable, Equatable {

    /// A thing by name, found when the job runs: matches scoring below
    /// `minimumScore` are ignored, and the edge is feathered by `feather`
    /// pixels.
    case named(String, minimumScore: Double, feather: Double)

    /// A mask already found.
    case mask(RegionMask)
}

/// A mask: `width × height` bytes, 255 inside, row-major from the top-left
/// pixel, with the edge feather to apply.
public struct RegionMask: Sendable, Codable, Equatable {

    public let width: Int
    public let height: Int
    public let pixels: Data
    public let feather: Double

    public init(width: Int, height: Int, pixels: Data, feather: Double) {
        self.width = width
        self.height = height
        self.pixels = pixels
        self.feather = feather
    }
}
