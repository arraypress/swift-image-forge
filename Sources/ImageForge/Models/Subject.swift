//
//  Subject.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation

/// What a picture turned out to be about, and where it is.
public struct Subject: Sendable, Codable, Equatable, Hashable {
    /// The region the subject occupies, in top-left origin pixels of the
    /// image it was found in. When several things were found this is their
    /// union, so a photo of two people centres between them.
    public let rect: CGRect
    /// What kind of thing it is.
    public let kind: SubjectKind
    /// How many were found — two faces, three cats.
    public let count: Int

    /// - Parameters:
    ///   - rect: The region, in top-left origin pixels.
    ///   - kind: What kind of thing was found.
    ///   - count: How many were found.
    public init(rect: CGRect, kind: SubjectKind, count: Int) {
        self.rect = rect
        self.kind = kind
        self.count = count
    }

    /// The middle of the subject — the point a crop is centred on.
    public var center: CGPoint {
        CGPoint(x: rect.midX, y: rect.midY)
    }

    /// A short phrase for a log or a table: `"2 faces"`, `"1 face"`.
    public var summary: String {
        let noun = kind == .attention ? "attention region" : kind.rawValue
        return count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }
}
