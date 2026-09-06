//
//  RotationAngle.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Right-angle rotation only. Arbitrary angles need a background colour, a
//  resampling policy and a new canvas size, which is a different operation
//  with different questions; this is the lossless quarter-turn.
//

import CoreGraphics
import Foundation

/// A clockwise rotation by a quarter turn.
public enum RotationAngle: Int, CaseIterable, Sendable, Codable, Hashable {
    case ninety = 90
    case oneEighty = 180
    case twoSeventy = 270

    /// Whether this rotation swaps width and height.
    public var swapsAxes: Bool { self == .ninety || self == .twoSeventy }

    /// The rotation in radians, clockwise.
    public var radians: CGFloat { CGFloat(rawValue) * .pi / 180 }
}
