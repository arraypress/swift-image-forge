//
//  PageSpec.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  How to find and flatten the page in a photograph of one: what shape to
//  give it, and how sure the detector has to be before its corners are
//  trusted over the whole frame.
//

import Foundation

/// How a photographed page is found and flattened.
public struct PageSpec: Sendable, Codable, Equatable, Hashable {
    /// Force the result to this sheet's shape, whatever was measured.
    public var paper: PaperSize?
    /// When no sheet is forced, use A4's or Letter's shape if the measured
    /// page is within 2% of one. Off by default: measured on real photographs
    /// it named the wrong sheet twice and the right one never. See
    /// ``PaperSize/nearest(to:tolerance:)``.
    public var snapsToPaper: Bool
    /// The detector confidence below which the page is treated as not found.
    /// See ``Detectors/MinimumConfidence/document``.
    public var minimumConfidence: Double

    /// - Parameters:
    ///   - paper: A sheet to force the shape to, or nil to measure it.
    ///   - snapsToPaper: Snap a measured shape to a nearby standard sheet.
    ///   - minimumConfidence: The detector floor.
    public init(paper: PaperSize? = nil, snapsToPaper: Bool = false,
                minimumConfidence: Double = Detectors.MinimumConfidence.document) {
        self.paper = paper
        self.snapsToPaper = snapsToPaper
        self.minimumConfidence = minimumConfidence
    }

    /// Measure the page and keep the shape measured.
    public static let automatic = PageSpec()
    /// Measure the page, and take A4's or Letter's shape when within 2%.
    public static let snapping = PageSpec(snapsToPaper: true)
}
