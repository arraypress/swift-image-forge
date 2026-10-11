//
//  LayerPlacement.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// Where a layer sits on the canvas and how large it is drawn.
///
/// The layer's own rectangle is what is placed; its effects spill around it.
/// Positions snap to whole pixels, so a layer drawn at its own size is not
/// resampled.
public struct LayerPlacement: Sendable, Codable, Equatable, Hashable {
    /// The side or corner the layer is pinned to. `.smart` is not accepted.
    public var anchor: Anchor
    /// How far the layer is kept from the edges it is pinned to. Ignored on
    /// an axis the anchor centres.
    public var inset: Length
    /// The layer's top-left corner, overriding `anchor` and `inset`.
    public var position: (x: Length, y: Length)?
    /// How large the layer is drawn.
    public var size: LayerSize

    /// - Parameters:
    ///   - anchor: Centre by default.
    ///   - inset: Distance from the pinned edges.
    ///   - position: An explicit top-left corner instead of an anchor.
    ///   - size: The layer's own size by default.
    public init(anchor: Anchor = .center, inset: Length = .zero,
                position: (x: Length, y: Length)? = nil, size: LayerSize = .original) {
        self.anchor = anchor
        self.inset = inset
        self.position = position
        self.size = size
    }

    /// Centred, at its own size.
    public static let centered = LayerPlacement()

    // A tuple is neither Codable nor Hashable, so these are written out.
    private enum CodingKeys: String, CodingKey { case anchor, inset, x, y, size }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        anchor = try container.decodeIfPresent(Anchor.self, forKey: .anchor) ?? .center
        inset = try container.decodeIfPresent(Length.self, forKey: .inset) ?? .zero
        size = try container.decodeIfPresent(LayerSize.self, forKey: .size) ?? .original
        let x = try container.decodeIfPresent(Length.self, forKey: .x)
        let y = try container.decodeIfPresent(Length.self, forKey: .y)
        position = (x != nil || y != nil) ? (x ?? .zero, y ?? .zero) : nil
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(anchor, forKey: .anchor)
        try container.encode(inset, forKey: .inset)
        try container.encode(size, forKey: .size)
        try container.encodeIfPresent(position?.x, forKey: .x)
        try container.encodeIfPresent(position?.y, forKey: .y)
    }

    public static func == (lhs: LayerPlacement, rhs: LayerPlacement) -> Bool {
        lhs.anchor == rhs.anchor && lhs.inset == rhs.inset && lhs.size == rhs.size
            && lhs.position?.x == rhs.position?.x && lhs.position?.y == rhs.position?.y
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(anchor)
        hasher.combine(inset)
        hasher.combine(size)
        hasher.combine(position?.x)
        hasher.combine(position?.y)
    }
}
