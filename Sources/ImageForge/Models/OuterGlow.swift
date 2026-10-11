//
//  OuterGlow.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Light around a layer's edge: its silhouette, softened outward. Drawn with
/// ordinary blending — this library composites source-over only.
public struct OuterGlow: Sendable, Codable, Equatable, Hashable {
    /// How far the glow reaches past the edge, in output pixels
    /// (σ = radius / 3, as for ``DropShadow/blur``).
    public var radius: Double
    /// The glow's colour.
    public var color: ForgeColor
    /// How strong it is, 0 to 1.
    public var opacity: Double

    /// - Parameters:
    ///   - radius: Reach in pixels.
    ///   - color: White by default.
    ///   - opacity: 0.75 by default.
    public init(radius: Double, color: ForgeColor = .white, opacity: Double = 0.75) {
        self.radius = radius
        self.color = color
        self.opacity = opacity
    }
}
