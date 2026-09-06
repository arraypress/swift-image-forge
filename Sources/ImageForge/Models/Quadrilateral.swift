//
//  Quadrilateral.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Four corners, in image pixels. A page photographed at an angle is not a
//  rectangle, and flattening it to its bounding box throws away exactly the
//  information needed to straighten it.
//

import CoreGraphics
import Foundation

/// A four-cornered shape found in an image, in top-left origin pixels.
public struct Quadrilateral: Sendable, Codable, Equatable, Hashable {
    /// The top-left corner.
    public let topLeft: CGPoint
    /// The top-right corner.
    public let topRight: CGPoint
    /// The bottom-right corner.
    public let bottomRight: CGPoint
    /// The bottom-left corner.
    public let bottomLeft: CGPoint
    /// How sure the detector was, from 0 to 1.
    public let confidence: Double

    /// - Parameters:
    ///   - topLeft: The top-left corner.
    ///   - topRight: The top-right corner.
    ///   - bottomRight: The bottom-right corner.
    ///   - bottomLeft: The bottom-left corner.
    ///   - confidence: How sure the detector was.
    public init(topLeft: CGPoint, topRight: CGPoint,
                bottomRight: CGPoint, bottomLeft: CGPoint, confidence: Double) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
        self.confidence = confidence
    }

    /// The four corners, clockwise from the top left.
    public var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    /// The smallest upright rectangle containing all four corners.
    public var boundingBox: CGRect {
        let xs = corners.map(\.x), ys = corners.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// How far the shape leans, in degrees, averaged over its two
    /// horizontal edges. Positive leans one way, negative the other.
    ///
    /// Measured as an angle rather than in pixels because a pixel tolerance
    /// means something different on a thumbnail and on a 40-megapixel scan:
    /// a detector two pixels out on a 400px page is 0.3° and on a 4000px
    /// page is 0.03°, and only one of those is worth resampling for.
    public var skewAngle: Double {
        let top = atan2(topRight.y - topLeft.y, topRight.x - topLeft.x)
        let bottom = atan2(bottomRight.y - bottomLeft.y, bottomRight.x - bottomLeft.x)
        return (top + bottom) / 2 * 180 / .pi
    }

    /// Whether the shape is close enough to upright that straightening it
    /// would not be worth the resampling.
    ///
    /// - Parameter degrees: How much lean to forgive.
    /// - Returns: True when the shape leans less than that.
    public func isUpright(withinDegrees degrees: Double = 1) -> Bool {
        abs(skewAngle) < degrees
    }
}
