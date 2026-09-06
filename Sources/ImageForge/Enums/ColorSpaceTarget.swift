//
//  ColorSpaceTarget.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Converting a wide-gamut screenshot to sRGB is the difference between a
//  brand colour that matches on the web and one that is subtly wrong.
//

import CoreGraphics
import Foundation

/// The colour space the output is converted to.
public enum ColorSpaceTarget: String, CaseIterable, Sendable, Codable, Hashable {
    /// Leave the image in whatever space it arrived in.
    case unchanged
    /// sRGB — the safe assumption for the web and for anything that will be
    /// opened by software that ignores profiles.
    case sRGB
    /// Display P3 — the wider gamut Apple displays and cameras work in.
    case displayP3
    /// Linear sRGB, for compositing and for handing pixels to a renderer.
    case linearSRGB
    /// Single-channel greyscale, gamma 2.2.
    case gray

    /// The Core Graphics colour space this names, or nil for `.unchanged`.
    public var colorSpace: CGColorSpace? {
        switch self {
        case .unchanged: return nil
        case .sRGB: return CGColorSpace(name: CGColorSpace.sRGB)
        case .displayP3: return CGColorSpace(name: CGColorSpace.displayP3)
        case .linearSRGB: return CGColorSpace(name: CGColorSpace.linearSRGB)
        case .gray: return CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)
        }
    }

    /// Whether converting to this space discards colour — a one-way trip.
    public var isMonochrome: Bool { self == .gray }
}
