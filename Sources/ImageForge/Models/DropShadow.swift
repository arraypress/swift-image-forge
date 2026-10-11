//
//  DropShadow.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// A shadow cast by a layer's silhouette.
///
/// `blur` is how far the edge softens, in output pixels — what Photoshop
/// calls Size. Internally it is a Gaussian with σ = blur / 3, measured from
/// Core Image's blur (its radius is σ to within 4%), so the shadow has faded
/// to nothing `blur` pixels past a hard edge.
public struct DropShadow: Sendable, Codable, Equatable, Hashable {
    /// Horizontal offset in output pixels; positive is right.
    public var offsetX: Double
    /// Vertical offset in output pixels; positive is down.
    public var offsetY: Double
    /// How far the edge softens, in output pixels. 0 is a hard shadow.
    public var blur: Double
    /// The shadow's colour.
    public var color: ForgeColor
    /// How strong it is, 0 to 1, on top of the colour's own alpha.
    public var opacity: Double

    /// - Parameters:
    ///   - offsetX: Pixels right.
    ///   - offsetY: Pixels down.
    ///   - blur: Softening distance in pixels.
    ///   - color: Black by default.
    ///   - opacity: 0.5 by default — a shadow, not a silhouette.
    public init(offsetX: Double = 0, offsetY: Double = 0, blur: Double = 0,
                color: ForgeColor = .black, opacity: Double = 0.5) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.blur = blur
        self.color = color
        self.opacity = opacity
    }
}
