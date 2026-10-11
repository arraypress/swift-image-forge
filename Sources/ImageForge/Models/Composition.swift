//
//  Composition.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation

/// Layers on a backdrop: what ``ImageForge/compose(_:)`` draws.
///
/// ```swift
/// // A product shot: the cut-out at 80% of a white square, with a soft shadow.
/// let shot = try ImageForge.compose(Composition(
///     backdrop: .color(.white), size: CGSize(width: 1200, height: 1200),
///     layers: [CompositeLayer(image: cutout, style: LayerStyle(
///         placement: LayerPlacement(size: .fit(0.8)),
///         effects: LayerEffects(shadow: DropShadow(offsetY: 24, blur: 40))))]))
/// ```
public struct Composition: Sendable {
    /// What the layers are drawn onto.
    public var backdrop: Backdrop
    /// The canvas, in pixels. Nil takes the backdrop image's size, or — with
    /// no backdrop image — exactly fits the first layer and its effects.
    public var size: CGSize?
    /// Bottom to top.
    public var layers: [CompositeLayer]

    /// - Parameters:
    ///   - backdrop: Transparent by default.
    ///   - size: The canvas size, or nil to derive it.
    ///   - layers: Bottom to top.
    public init(backdrop: Backdrop = .clear, size: CGSize? = nil, layers: [CompositeLayer]) {
        self.backdrop = backdrop
        self.size = size
        self.layers = layers
    }
}
