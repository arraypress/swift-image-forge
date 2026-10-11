//
//  LayerEffects.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// The effects drawn around one layer, bottom to top: shadow, glow, stroke,
/// then the layer itself.
public struct LayerEffects: Sendable, Codable, Equatable, Hashable {
    /// An outline outside the edge.
    public var stroke: LayerStroke?
    /// A cast shadow.
    public var shadow: DropShadow?
    /// Light around the edge.
    public var glow: OuterGlow?

    /// - Parameters:
    ///   - stroke: An outline, or none.
    ///   - shadow: A shadow, or none.
    ///   - glow: A glow, or none.
    public init(stroke: LayerStroke? = nil, shadow: DropShadow? = nil, glow: OuterGlow? = nil) {
        self.stroke = stroke
        self.shadow = shadow
        self.glow = glow
    }

    /// No effects.
    public static let none = LayerEffects()

    /// Whether there is anything to draw besides the layer.
    public var isEmpty: Bool { stroke == nil && shadow == nil && glow == nil }
}
