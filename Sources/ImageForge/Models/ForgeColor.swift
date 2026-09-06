//
//  ForgeColor.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  A plain sRGB colour with no UI framework behind it, serialised as
//  {red, green, blue, alpha} — the same shape as VideoGrade's `GradeColor`
//  and CaptionKit's `StyleColor`, so a colour written by one of those
//  documents still decodes here.
//

import CoreGraphics
import Foundation

/// A colour in sRGB, each component from 0 to 1.
public struct ForgeColor: Sendable, Codable, Equatable, Hashable {
    /// Red, 0 to 1.
    public var red: Double
    /// Green, 0 to 1.
    public var green: Double
    /// Blue, 0 to 1.
    public var blue: Double
    /// Opacity, 0 (clear) to 1 (solid).
    public var alpha: Double

    /// - Parameters:
    ///   - red: Red, 0 to 1.
    ///   - green: Green, 0 to 1.
    ///   - blue: Blue, 0 to 1.
    ///   - alpha: Opacity, 0 to 1. Solid by default.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Fully transparent — the default background for a format that keeps alpha.
    public static let clear = ForgeColor(red: 0, green: 0, blue: 0, alpha: 0)
    /// Opaque white — the background a JPEG gets when the source had alpha.
    public static let white = ForgeColor(red: 1, green: 1, blue: 1)
    /// Opaque black.
    public static let black = ForgeColor(red: 0, green: 0, blue: 0)

    /// A colour from `#RGB`, `#RRGGBB` or `#RRGGBBAA`. The hash is optional.
    /// Returns nil for anything else, so a bad value from a config file is
    /// a caller's error to report rather than a silent black.
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6 || text.count == 8,
              text.allSatisfy({ $0.isHexDigit }),
              let value = UInt32(text, radix: 16) else { return nil }
        let hasAlpha = text.count == 8
        let r = hasAlpha ? (value >> 24) & 0xFF : (value >> 16) & 0xFF
        let g = hasAlpha ? (value >> 16) & 0xFF : (value >> 8) & 0xFF
        let b = hasAlpha ? (value >> 8) & 0xFF : value & 0xFF
        let a = hasAlpha ? value & 0xFF : 255
        self.init(red: Double(r) / 255, green: Double(g) / 255,
                  blue: Double(b) / 255, alpha: Double(a) / 255)
    }

    /// `#RRGGBB`, or `#RRGGBBAA` when the colour is not fully opaque.
    public var hex: String {
        let r = Int((red * 255).rounded()), g = Int((green * 255).rounded())
        let b = Int((blue * 255).rounded()), a = Int((alpha * 255).rounded())
        return a == 255
            ? String(format: "#%02X%02X%02X", r, g, b)
            : String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }

    /// The Core Graphics colour, in sRGB.
    public var cgColor: CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                components: [CGFloat(red), CGFloat(green), CGFloat(blue), CGFloat(alpha)])
            ?? CGColor(gray: 0, alpha: CGFloat(alpha))
    }
}
