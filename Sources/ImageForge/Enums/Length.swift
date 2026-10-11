//
//  Length.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  A distance on a canvas, either fixed or relative to the canvas — so a
//  watermark can sit 24 px from the corner or 3% in, whatever the size.
//

import CoreGraphics
import Foundation

/// A distance in canvas pixels, or a share of a canvas dimension.
public enum Length: Sendable, Codable, Equatable, Hashable {
    /// A fixed number of output pixels.
    case pixels(Double)
    /// A percentage of the canvas dimension it is measured along — the
    /// width for a horizontal distance, the height for a vertical one.
    case percent(Double)

    /// No distance at all.
    public static let zero = Length.pixels(0)

    /// The distance in pixels along a dimension of the given extent.
    ///
    /// - Parameter extent: The canvas width or height the distance runs along.
    /// - Returns: Pixels.
    public func resolved(along extent: CGFloat) -> CGFloat {
        switch self {
        case .pixels(let value): return CGFloat(value)
        case .percent(let value): return extent * CGFloat(value) / 100
        }
    }
}
