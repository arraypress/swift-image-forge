//
//  EncodeSpec.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Everything about the file that comes out, as opposed to the pixels that
//  go into it.
//

import Foundation

/// How an image is written.
public struct EncodeSpec: Sendable, Codable, Equatable, Hashable {
    /// The container to write. Nil keeps the source's own format.
    public var format: ImageFormat?
    /// Lossy quality, 0 (smallest) to 1 (best). Ignored by lossless formats.
    public var quality: Double
    /// Write no more than this many bytes, by searching for the quality that
    /// fits. Nil leaves `quality` alone. See ``TargetSize`` for the search.
    public var maximumBytes: Int?
    /// What metadata reaches the output.
    public var metadata: MetadataPolicy
    /// What happens to an HDR gain map.
    public var hdr: HDRPolicy
    /// The colour space to convert to on the way out.
    public var colorSpace: ColorSpaceTarget
    /// The colour composited behind the image when the target format cannot
    /// carry alpha. White by default, which is what a JPEG of a logo needs.
    public var matte: ForgeColor
    /// Ask the encoder to reorder a JPEG for progressive display, and to
    /// prefer settings that survive re-compression by messaging apps.
    public var optimizeForSharing: Bool

    /// - Parameters:
    ///   - format: The container to write, or nil to keep the source's.
    ///   - quality: Lossy quality from 0 to 1.
    ///   - maximumBytes: A byte budget to search for, or nil for none.
    ///   - metadata: What metadata survives. Location is dropped by default.
    ///   - hdr: What happens to a gain map. Preserved by default.
    ///   - colorSpace: The output colour space. Unchanged by default.
    ///   - matte: What sits behind the image when alpha cannot be kept.
    ///   - optimizeForSharing: Whether to ask the encoder to optimise for sharing.
    public init(format: ImageFormat? = nil,
                quality: Double = 0.85,
                maximumBytes: Int? = nil,
                metadata: MetadataPolicy = .stripLocation,
                hdr: HDRPolicy = .preserve,
                colorSpace: ColorSpaceTarget = .unchanged,
                matte: ForgeColor = .white,
                optimizeForSharing: Bool = false) {
        self.format = format
        self.quality = min(1, max(0, quality))
        self.maximumBytes = maximumBytes.map { max(1, $0) }
        self.metadata = metadata
        self.hdr = hdr
        self.colorSpace = colorSpace
        self.matte = matte
        self.optimizeForSharing = optimizeForSharing
    }

    /// Write this format at the default quality.
    public static func format(_ format: ImageFormat, quality: Double = 0.85) -> EncodeSpec {
        EncodeSpec(format: format, quality: quality)
    }

    /// Fit inside a byte budget, whatever quality that takes.
    public static func underBytes(_ bytes: Int, format: ImageFormat? = nil) -> EncodeSpec {
        EncodeSpec(format: format, maximumBytes: bytes)
    }

    /// Keep everything the source carried, including its location.
    public static let lossless = EncodeSpec(format: .png, metadata: .keep)
}
