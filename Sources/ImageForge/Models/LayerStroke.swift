//
//  LayerStroke.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// An outline drawn outside a layer's edge, the way Photoshop's Stroke does
/// with its position set to Outside: the layer's own pixels are never covered.
public struct LayerStroke: Sendable, Codable, Equatable, Hashable {
    /// How far the outline reaches beyond the edge, in output pixels.
    public var width: Double
    /// The outline's colour; its alpha is the outline's opacity.
    public var color: ForgeColor

    /// - Parameters:
    ///   - width: Output pixels beyond the edge.
    ///   - color: The colour. White by default — the sticker look.
    public init(width: Double, color: ForgeColor = .white) {
        self.width = width
        self.color = color
    }
}
