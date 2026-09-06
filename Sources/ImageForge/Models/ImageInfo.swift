//
//  ImageInfo.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  What a file is, read from its header without decoding the pixels — so
//  describing a folder of 50-megapixel RAWs costs milliseconds.
//

import CoreGraphics
import Foundation

/// What an image file contains.
public struct ImageInfo: Sendable, Codable, Equatable, Hashable {
    /// Width in pixels, with the EXIF orientation already applied — the
    /// number a person looking at the picture would give.
    public let width: Int
    /// Height in pixels, orientation applied.
    public let height: Int
    /// Width as the pixels are actually stored, before orientation.
    public let storedWidth: Int
    /// Height as stored, before orientation.
    public let storedHeight: Int
    /// The named format, or nil for one this library has no case for — RAW,
    /// DICOM, a GPU texture. `typeIdentifier` still names it.
    public let format: ImageFormat?
    /// The uniform type identifier ImageIO recognised.
    public let typeIdentifier: String
    /// The EXIF orientation, 1 to 8. 1 means "already upright".
    public let orientation: Int
    /// Whether the image has an alpha channel.
    public let hasAlpha: Bool
    /// Bits per colour component — 8 for an ordinary photo, 16 or 32 for
    /// deep or floating-point formats.
    public let bitsPerComponent: Int
    /// The name of the colour space the file declares, if it declares one.
    public let colorSpaceName: String?
    /// Whether the file carries an HDR gain map beside its base image.
    public let hasGainMap: Bool
    /// How many frames the file holds. 1 for a still.
    public let frameCount: Int
    /// The size of the file on disk, in bytes. Nil when read from data.
    public let byteCount: Int?
    /// Whether the file records where it was taken.
    public let hasLocation: Bool
    /// The capture date the file records, if any.
    public let capturedAt: Date?

    /// - Parameters:
    ///   - width: Width in pixels, orientation applied.
    ///   - height: Height in pixels, orientation applied.
    ///   - storedWidth: Width as stored, before orientation.
    ///   - storedHeight: Height as stored, before orientation.
    ///   - format: The named format, if there is a case for it.
    ///   - typeIdentifier: The uniform type identifier ImageIO recognised.
    ///   - orientation: The EXIF orientation, 1 to 8.
    ///   - hasAlpha: Whether there is an alpha channel.
    ///   - bitsPerComponent: Bits per colour component.
    ///   - colorSpaceName: The declared colour space's name, if any.
    ///   - hasGainMap: Whether an HDR gain map is present.
    ///   - frameCount: How many frames the file holds.
    ///   - byteCount: File size in bytes, if known.
    ///   - hasLocation: Whether GPS coordinates are recorded.
    ///   - capturedAt: The recorded capture date, if any.
    public init(width: Int, height: Int, storedWidth: Int, storedHeight: Int,
                format: ImageFormat?, typeIdentifier: String, orientation: Int,
                hasAlpha: Bool, bitsPerComponent: Int, colorSpaceName: String?,
                hasGainMap: Bool, frameCount: Int, byteCount: Int?,
                hasLocation: Bool, capturedAt: Date?) {
        self.width = width
        self.height = height
        self.storedWidth = storedWidth
        self.storedHeight = storedHeight
        self.format = format
        self.typeIdentifier = typeIdentifier
        self.orientation = orientation
        self.hasAlpha = hasAlpha
        self.bitsPerComponent = bitsPerComponent
        self.colorSpaceName = colorSpaceName
        self.hasGainMap = hasGainMap
        self.frameCount = frameCount
        self.byteCount = byteCount
        self.hasLocation = hasLocation
        self.capturedAt = capturedAt
    }

    /// Whether the file holds an animation rather than a still.
    public var isAnimated: Bool { frameCount > 1 }

    /// Width over height, orientation applied.
    public var aspectRatio: Double {
        height == 0 ? 0 : Double(width) / Double(height)
    }

    /// How many pixels the image has, in millions.
    public var megapixels: Double {
        Double(width) * Double(height) / 1_000_000
    }

    /// Whether the stored pixels need rotating before they look right.
    public var needsOrientationFix: Bool { orientation != 1 }
}
