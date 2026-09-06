//
//  CropSpec.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Three ways to say what to keep: an explicit rectangle, an aspect ratio
//  taken from an anchor, or an inset from the edges.
//

import CoreGraphics
import Foundation

/// What part of an image to keep.
public enum CropSpec: Sendable, Codable, Equatable, Hashable {
    /// An explicit rectangle in pixels, origin at the **top left** — the
    /// same convention the `pdf` tool uses, and the one a person reading
    /// coordinates off a screenshot expects.
    case rect(x: Int, y: Int, width: Int, height: Int)
    /// The largest rectangle of this aspect ratio that fits, pinned to the
    /// anchor. `aspect(16, 9, .smart)` is the crop a thumbnail wants.
    case aspect(width: Int, height: Int, anchor: Anchor)
    /// Trim this many pixels off each edge.
    case inset(top: Int, left: Int, bottom: Int, right: Int)
    /// Trim fully transparent rows and columns from the edges. Useful after
    /// a background removal, where the subject floats in a large clear field.
    case trimTransparent(tolerance: Double)
    /// Keep the detected subject and nothing else — the page in a photo of
    /// a document, the cat, the two faces — with a margin around it given as
    /// a fraction of the subject's own size.
    ///
    /// Falls back to the whole image when nothing is found, because cropping
    /// to a guess is worse than not cropping.
    case subject(padding: Double)

    /// A square, pinned to the anchor.
    public static func square(anchor: Anchor = .center) -> CropSpec {
        .aspect(width: 1, height: 1, anchor: anchor)
    }

    /// Whether resolving this crop needs Vision, and so needs `await`.
    public var needsAnalysis: Bool {
        switch self {
        case .aspect(_, _, let anchor): return anchor.needsAnalysis
        case .subject: return true
        default: return false
        }
    }
}
