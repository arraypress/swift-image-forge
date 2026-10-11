//
//  CompositeLayer.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation

/// One image placed on a canvas, with its effects.
public struct CompositeLayer: Sendable {
    /// The pixels — usually with transparency, such as a cut-out subject.
    public var image: CGImage
    /// Placement, effects and opacity.
    public var style: LayerStyle

    /// - Parameters:
    ///   - image: The pixels.
    ///   - style: How it is drawn.
    public init(image: CGImage, style: LayerStyle = LayerStyle()) {
        self.image = image
        self.style = style
    }
}
