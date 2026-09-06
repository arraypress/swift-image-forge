//
//  Anchor.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Where a smaller rectangle sits inside a larger one — which part of a
//  photo survives a crop, or where a small image lands on a large canvas.
//

import CoreGraphics
import Foundation

/// The point a crop or a placement is pinned to.
///
/// `.smart` is the only case that looks at the picture: it asks Vision which
/// region draws the eye and centres on that, which keeps faces and subjects
/// in frame where `.center` would cut them in half. Because it runs a model
/// it is resolved asynchronously — see ``ImageForge/process(_:to:options:)``.
public enum Anchor: String, CaseIterable, Sendable, Codable, Hashable {
    case topLeft, top, topRight
    case left, center, right
    case bottomLeft, bottom, bottomRight
    /// Wherever Vision says the subject is.
    case smart

    /// The horizontal share of the leftover space that goes on the left,
    /// from 0 (flush left) to 1 (flush right). Nil for `.smart`, which has
    /// no fixed answer.
    public var horizontalBias: CGFloat? {
        switch self {
        case .topLeft, .left, .bottomLeft: return 0
        case .top, .center, .bottom: return 0.5
        case .topRight, .right, .bottomRight: return 1
        case .smart: return nil
        }
    }

    /// The vertical share of the leftover space that goes on top, from 0
    /// (flush top) to 1 (flush bottom). Nil for `.smart`.
    ///
    /// Measured downward, in image coordinates, so 0 is the top row of pixels.
    public var verticalBias: CGFloat? {
        switch self {
        case .topLeft, .top, .topRight: return 0
        case .left, .center, .right: return 0.5
        case .bottomLeft, .bottom, .bottomRight: return 1
        case .smart: return nil
        }
    }

    /// Whether resolving this anchor needs Vision, and so needs `await`.
    public var needsAnalysis: Bool { self == .smart }
}
