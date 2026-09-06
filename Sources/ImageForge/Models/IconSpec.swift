//
//  IconSpec.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  ImageIO writes both icon containers — `.icns` and `.ico` — which means
//  a whole icon set is a pure ImageIO job with nothing else installed.
//

import Foundation

/// The set of square sizes an icon file or asset set is built from.
public struct IconSpec: Sendable, Codable, Equatable, Hashable {
    /// The square edge lengths in pixels, largest first when written.
    public var sizes: [Int]
    /// The colour composited behind a transparent source. Clear keeps the
    /// transparency, which is what an app icon with rounded corners needs.
    public var background: ForgeColor

    /// - Parameters:
    ///   - sizes: Square edge lengths in pixels. Duplicates are removed.
    ///   - background: What sits behind a transparent source.
    public init(sizes: [Int], background: ForgeColor = .clear) {
        self.sizes = Array(Set(sizes.filter { $0 > 0 })).sorted(by: >)
        self.background = background
    }

    /// Every size an `.icns` accepts. Note the gaps — no 64, no 1024 —
    /// which are measured, not chosen; see ``IconSizes``.
    public static let macOS = IconSpec(sizes: IconSizes.icns)

    /// Every size an `.ico` accepts.
    public static let windows = IconSpec(sizes: IconSizes.ico)

    /// A favicon's usual sizes, kept to ones `.ico` will take. The 180px
    /// an `apple-touch-icon` wants is not among them — write that as a
    /// separate PNG with ``ImageForge/iconSet(_:into:spec:format:overwrites:)``.
    public static let favicon = IconSpec(sizes: [64, 32, 16])

    /// One source rendered at 1×, 2× and 3× — the Apple asset-catalog set.
    public static func scaleFactors(base: Int) -> IconSpec {
        IconSpec(sizes: [base, base * 2, base * 3])
    }
}
