//
//  ScannedPage.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  What a photograph of a page became, and how: the flat page itself, the
//  corners it was cut from, and whether those corners were found at all —
//  because a scan that quietly kept the whole frame looks like a success.
//

import CoreGraphics
import Foundation

/// A photographed page, flattened and cleaned.
public struct ScannedPage: @unchecked Sendable {
    /// The page.
    public let image: CGImage
    /// The size of the photograph it came from, in pixels.
    public let sourceSize: CGSize
    /// The page's corners in the photograph, in top-left origin pixels, or
    /// nil when no page was found and the whole frame was kept.
    public let corners: Quadrilateral?
    /// The sheet the page's shape was matched to, if any.
    public let paper: PaperSize?
    /// The steps that ran, with the page detection resolved to the corners
    /// it found.
    public let operations: [ImageOperation]

    /// - Parameters:
    ///   - image: The page.
    ///   - sourceSize: The photograph's size.
    ///   - corners: Where the page was found, or nil.
    ///   - paper: The sheet matched, if any.
    ///   - operations: The steps that ran.
    public init(image: CGImage, sourceSize: CGSize, corners: Quadrilateral?,
                paper: PaperSize?, operations: [ImageOperation]) {
        self.image = image
        self.sourceSize = sourceSize
        self.corners = corners
        self.paper = paper
        self.operations = operations
    }

    /// Whether a page was found and flattened, rather than the frame kept.
    public var foundPage: Bool { corners != nil }
}
