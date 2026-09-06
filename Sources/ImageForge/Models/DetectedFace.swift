//
//  DetectedFace.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation

/// A face found in an image.
public struct DetectedFace: Sendable, Codable, Equatable, Hashable {
    /// Where it is, in top-left origin pixels.
    public let rect: CGRect
    /// How sure the detector was, from 0 to 1.
    public let confidence: Double
    /// Tilt of the head towards a shoulder, in degrees.
    public let roll: Double
    /// Turn of the head left or right, in degrees.
    public let yaw: Double
    /// Tilt of the head up or down, in degrees.
    public let pitch: Double
    /// How usable the face is for recognition, from 0 to 1 — sharpness,
    /// lighting and pose together. Nil when it was not measured.
    ///
    /// Useful for choosing between frames: the best shot of a burst is the
    /// one where this is highest.
    public let quality: Double?

    /// - Parameters:
    ///   - rect: Where the face is, in top-left origin pixels.
    ///   - confidence: How sure the detector was.
    ///   - roll: Tilt towards a shoulder, in degrees.
    ///   - yaw: Turn left or right, in degrees.
    ///   - pitch: Tilt up or down, in degrees.
    ///   - quality: How usable the face is, if measured.
    public init(rect: CGRect, confidence: Double, roll: Double, yaw: Double,
                pitch: Double, quality: Double?) {
        self.rect = rect
        self.confidence = confidence
        self.roll = roll
        self.yaw = yaw
        self.pitch = pitch
        self.quality = quality
    }

    /// Whether the face is turned far enough away that it is a profile
    /// rather than a portrait.
    public var isProfile: Bool { abs(yaw) > 45 }
}
