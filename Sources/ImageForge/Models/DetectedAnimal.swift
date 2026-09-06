//
//  DetectedAnimal.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation

/// An animal found in an image.
///
/// Vision recognises cats and dogs. It does not recognise anything else, so
/// a photograph of a horse comes back empty rather than wrong.
public struct DetectedAnimal: Sendable, Codable, Equatable, Hashable {
    /// Where it is, in top-left origin pixels.
    public let rect: CGRect
    /// What it is — `"Cat"` or `"Dog"`, as Vision spells it.
    public let label: String
    /// How sure the detector was, from 0 to 1.
    public let confidence: Double

    /// - Parameters:
    ///   - rect: Where it is, in top-left origin pixels.
    ///   - label: What it is.
    ///   - confidence: How sure the detector was.
    public init(rect: CGRect, label: String, confidence: Double) {
        self.rect = rect
        self.label = label
        self.confidence = confidence
    }
}
