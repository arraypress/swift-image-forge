//
//  DetectedPerson.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation

/// A person found in an image, whether or not their face is visible.
public struct DetectedPerson: Sendable, Codable, Equatable, Hashable {
    /// Where they are, in top-left origin pixels.
    public let rect: CGRect
    /// How sure the detector was, from 0 to 1.
    public let confidence: Double
    /// Whether only the upper body was found — someone behind a desk, or
    /// cut off by the frame.
    public let isUpperBodyOnly: Bool

    /// - Parameters:
    ///   - rect: Where they are, in top-left origin pixels.
    ///   - confidence: How sure the detector was.
    ///   - isUpperBodyOnly: Whether only the upper body was found.
    public init(rect: CGRect, confidence: Double, isUpperBodyOnly: Bool) {
        self.rect = rect
        self.confidence = confidence
        self.isUpperBodyOnly = isUpperBodyOnly
    }
}
