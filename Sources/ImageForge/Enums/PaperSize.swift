//
//  PaperSize.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  The sheets a photographed page is most likely to be. A perspective
//  correction recovers a page's shape only approximately — foreshortening
//  makes the far edge look shorter than it is — and on real photographs the
//  shape alone proved too weak to name the sheet, so matching is opt-in.
//

import CoreGraphics
import Foundation

/// A standard sheet of paper.
public enum PaperSize: String, CaseIterable, Sendable, Codable, Hashable {
    /// ISO A4, 210 × 297 mm. Everywhere but North America.
    case a4
    /// ISO A5, 148 × 210 mm.
    case a5
    /// US Letter, 8.5 × 11 in.
    case letter
    /// US Legal, 8.5 × 14 in.
    case legal

    /// The sheet's size in PDF points, portrait.
    public var points: CGSize {
        switch self {
        case .a4: return CGSize(width: 595.28, height: 841.89)
        case .a5: return CGSize(width: 419.53, height: 595.28)
        case .letter: return CGSize(width: 612, height: 792)
        case .legal: return CGSize(width: 612, height: 1008)
        }
    }

    /// Height over width, portrait — above 1 for every sheet here.
    public var aspectRatio: Double { Double(points.height / points.width) }

    /// The sheet whose shape is closest to a measured one, if any is close
    /// enough to be believed. Only A4 and Letter are offered: they are the
    /// sheets a shape could plausibly be, and Legal was one of the two wrong
    /// answers this gave on real photographs.
    ///
    /// MEASURED on ten real photographed pages (Wikimedia Commons): shape
    /// matching never once named the right sheet, and named the wrong one
    /// twice — a Swiss hotel bill measured 1.608 and became Legal (2.4% off),
    /// a framed sign 1.260 and became Letter (2.6% off), while a real A4
    /// letter shot at an angle measured 1.14, foreshortened far past any
    /// tolerance. So matching is something a caller opts into, at 2% — under
    /// both wrong answers — and the default keeps the measured shape.
    ///
    /// - Parameters:
    ///   - size: The measured page, either way up.
    ///   - tolerance: How far the shapes may differ, as a fraction.
    /// - Returns: The sheet, or nil when nothing is that close.
    public static func nearest(to size: CGSize, tolerance: Double = 0.02) -> PaperSize? {
        guard size.width > 0, size.height > 0 else { return nil }
        let ratio = Double(max(size.width, size.height) / min(size.width, size.height))
        return [PaperSize.a4, .letter]
            .map { ($0, abs($0.aspectRatio - ratio) / $0.aspectRatio) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?.0
    }
}
