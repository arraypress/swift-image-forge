//
//  CollageResult.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation

/// A collage, made.
public struct CollageResult: Sendable, Equatable {
    /// Where it was written; nil for one rendered in memory.
    public let destination: URL?
    /// The canvas size, in pixels.
    public let size: CGSize
    /// Every photo's place, in drawing order.
    public let cells: [CollageCell]
    /// The seed actually used — the one given, or the one picked.
    public let seed: UInt64
    /// The bytes written, or 0 in memory.
    public let bytes: Int
    /// The container written.
    public let format: ImageFormat?
}
