//
//  MetadataPolicy.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  What of a file's EXIF, IPTC and XMP reaches the output. The default is
//  deliberately not "keep everything": a photo straight off a phone carries
//  the coordinates of the house it was taken in, and a resize for the web
//  is exactly when that leaks.
//

import Foundation

/// Which metadata survives an encode.
public enum MetadataPolicy: String, CaseIterable, Sendable, Codable, Hashable {
    /// Every dictionary the source carried — EXIF, IPTC, XMP, GPS, maker notes.
    case keep
    /// Everything except location: GPS is dropped, the rest is kept. The
    /// default, because it is what a person sharing a photo means by "keep
    /// my camera settings".
    case stripLocation
    /// Camera and capture data only: EXIF and TIFF, no GPS, no IPTC, no XMP,
    /// no maker notes. Keeps exposure and lens; drops authorship and history.
    case captureOnly
    /// Nothing at all. Orientation is baked into the pixels first, so the
    /// image still appears the right way up.
    case strip

    /// Whether any location information is allowed through.
    public var allowsLocation: Bool { self == .keep }
}
