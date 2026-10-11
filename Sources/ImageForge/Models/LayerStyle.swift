//
//  LayerStyle.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Everything about a layer except its pixels — data a recipe can carry.
public struct LayerStyle: Sendable, Codable, Equatable, Hashable {
    /// Where it goes and how large.
    public var placement: LayerPlacement
    /// Stroke, shadow, glow.
    public var effects: LayerEffects
    /// The layer's opacity, 0 to 1. Its effects fade with it, as a layer's
    /// opacity does in Photoshop.
    public var opacity: Double

    /// - Parameters:
    ///   - placement: Centred at its own size by default.
    ///   - effects: None by default.
    ///   - opacity: Solid by default.
    public init(placement: LayerPlacement = .centered, effects: LayerEffects = .none,
                opacity: Double = 1) {
        self.placement = placement
        self.effects = effects
        self.opacity = opacity
    }
}
