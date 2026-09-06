//
//  PadSpec.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Growing the canvas rather than the image: letterboxing to a fixed shape,
//  adding a print border, or giving a transparent logo a solid background
//  before it goes somewhere that cannot show alpha.
//

import CoreGraphics
import Foundation

/// Extra canvas around an image.
public struct PadSpec: Sendable, Codable, Equatable, Hashable {
    /// Pixels added above the image.
    public var top: Int
    /// Pixels added to the left.
    public var left: Int
    /// Pixels added below.
    public var bottom: Int
    /// Pixels added to the right.
    public var right: Int
    /// What fills the new space.
    public var color: ForgeColor

    /// - Parameters:
    ///   - top: Pixels added above.
    ///   - left: Pixels added to the left.
    ///   - bottom: Pixels added below.
    ///   - right: Pixels added to the right.
    ///   - color: The fill. Transparent by default.
    public init(top: Int = 0, left: Int = 0, bottom: Int = 0, right: Int = 0,
                color: ForgeColor = .clear) {
        self.top = max(0, top)
        self.left = max(0, left)
        self.bottom = max(0, bottom)
        self.right = max(0, right)
        self.color = color
    }

    /// The same padding on every edge.
    public static func all(_ pixels: Int, color: ForgeColor = .clear) -> PadSpec {
        PadSpec(top: pixels, left: pixels, bottom: pixels, right: pixels, color: color)
    }

    /// Total pixels added horizontally.
    public var horizontal: Int { left + right }
    /// Total pixels added vertically.
    public var vertical: Int { top + bottom }
    /// Whether this pad would change anything.
    public var isEmpty: Bool { horizontal == 0 && vertical == 0 }
}
