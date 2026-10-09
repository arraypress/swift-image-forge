//
//  PaperSize.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  The sheets a photographed page is most likely to be. A perspective
//  correction recovers a page's shape only approximately — foreshortening
//  makes the far edge look shorter than it is — so when the corrected shape
//  is within a few percent of a real sheet, the real sheet is the better
//  answer.
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
    /// enough to be believed.
    ///
    /// A4 and A5 share a shape, so a page that matches both comes back as
    /// A4, the commoner of the two.
    ///
    /// - Parameters:
    ///   - size: The measured page, either way up.
    ///   - tolerance: How far the shapes may differ, as a fraction. Letter
    ///     (1.294) and A4 (1.414) are 9% apart, so anything much over 0.04
    ///     starts confusing the two.
    /// - Returns: The sheet, or nil when nothing is that close — a receipt,
    ///   a business card, a page torn from a notebook.
    public static func nearest(to size: CGSize, tolerance: Double = 0.04) -> PaperSize? {
        guard size.width > 0, size.height > 0 else { return nil }
        let ratio = Double(max(size.width, size.height) / min(size.width, size.height))
        return [PaperSize.a4, .letter, .legal]
            .map { ($0, abs($0.aspectRatio - ratio) / $0.aspectRatio) }
            .filter { $0.1 <= tolerance }
            .min { $0.1 < $1.1 }?.0
    }
}
