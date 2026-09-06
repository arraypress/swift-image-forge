//
//  ImageDecoder.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Reading. Two things here are worth knowing. First, describing a file
//  never decodes it: the header alone answers size, format, orientation and
//  whether there is a gain map, so a folder of 50-megapixel RAWs can be
//  listed in milliseconds. Second, decoding goes through the thumbnail API
//  even at full size, because that is the call that applies the EXIF
//  orientation for you — `CGImageSourceCreateImageAtIndex` hands back the
//  pixels exactly as stored, still lying on their side.
//

import CoreGraphics
import Foundation
import ImageIO

/// Reads images and what is in them.
public enum ImageDecoder {

    // MARK: - Describing

    /// What an image file contains, read from its header.
    ///
    /// - Parameter url: The file to describe.
    /// - Returns: Everything known without decoding the pixels.
    /// - Throws: ``ImageForgeError/fileNotFound(_:)`` or
    ///   ``ImageForgeError/unreadable(_:)``.
    public static func describe(_ url: URL) throws -> ImageInfo {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImageForgeError.fileNotFound(url)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageForgeError.unreadable(url)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return try describe(source: source, byteCount: attributes?[.size] as? Int, name: url)
    }

    /// What a block of image data contains.
    ///
    /// - Parameter data: The bytes to describe.
    /// - Returns: Everything known without decoding the pixels.
    /// - Throws: ``ImageForgeError/unreadable(_:)``.
    public static func describe(_ data: Data) throws -> ImageInfo {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageForgeError.unreadable(URL(fileURLWithPath: "<data>"))
        }
        return try describe(source: source, byteCount: data.count,
                            name: URL(fileURLWithPath: "<data>"))
    }

    /// The shared body of both `describe` overloads.
    static func describe(source: CGImageSource, byteCount: Int?, name: URL) throws -> ImageInfo {
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw ImageForgeError.noImage(name) }

        let properties = properties(of: source, at: 0)
        let typeIdentifier = (CGImageSourceGetType(source) as String?) ?? "public.data"

        let storedWidth = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let storedHeight = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        // A source can open and still have no pixels: ImageIO recognises a
        // PDF's type but reports no dimensions for it, and answering 0×0 is
        // worse than refusing, because a batch then carries the nonsense
        // forward instead of skipping the file.
        guard storedWidth > 0, storedHeight > 0 else { throw ImageForgeError.noImage(name) }
        let orientation = properties[kCGImagePropertyOrientation as String] as? Int ?? 1
        let stored = CGSize(width: storedWidth, height: storedHeight)
        let displayed = Orientation.displayedSize(stored: stored, exif: orientation)

        return ImageInfo(
            width: Int(displayed.width),
            height: Int(displayed.height),
            storedWidth: storedWidth,
            storedHeight: storedHeight,
            format: ImageFormat.named(typeIdentifier: typeIdentifier),
            typeIdentifier: typeIdentifier,
            orientation: orientation,
            hasAlpha: properties[kCGImagePropertyHasAlpha as String] as? Bool ?? false,
            bitsPerComponent: properties[kCGImagePropertyDepth as String] as? Int ?? 8,
            colorSpaceName: properties[kCGImagePropertyProfileName as String] as? String,
            hasGainMap: hasGainMap(source),
            frameCount: count,
            byteCount: byteCount,
            hasLocation: Metadata.hasLocation(properties),
            capturedAt: Metadata.captureDate(properties)
        )
    }

    // MARK: - Decoding

    /// Decodes one image from a file.
    ///
    /// - Parameters:
    ///   - url: The file to read.
    ///   - index: Which frame, for a file that holds several.
    ///   - maxPixelSize: Decode no larger than this on the longest side.
    ///     Passing the size you are about to scale to turns a 50-megapixel
    ///     decode into a small one, which is most of the cost of a batch.
    ///   - applyOrientation: Turn the pixels the right way up. On by default.
    /// - Returns: The decoded image.
    /// - Throws: ``ImageForgeError/unreadable(_:)`` or ``ImageForgeError/noImage(_:)``.
    public static func image(at url: URL, index: Int = 0, maxPixelSize: Int? = nil,
                             applyOrientation: Bool = true) throws -> CGImage {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImageForgeError.fileNotFound(url)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageForgeError.unreadable(url)
        }
        return try image(from: source, at: index, maxPixelSize: maxPixelSize,
                         applyOrientation: applyOrientation, name: url)
    }

    /// Decodes one image from data.
    ///
    /// - Parameters:
    ///   - data: The bytes to read.
    ///   - index: Which frame, for data that holds several.
    ///   - maxPixelSize: Decode no larger than this on the longest side.
    ///   - applyOrientation: Turn the pixels the right way up.
    /// - Returns: The decoded image.
    /// - Throws: ``ImageForgeError/unreadable(_:)`` or ``ImageForgeError/noImage(_:)``.
    public static func image(from data: Data, index: Int = 0, maxPixelSize: Int? = nil,
                             applyOrientation: Bool = true) throws -> CGImage {
        let name = URL(fileURLWithPath: "<data>")
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageForgeError.unreadable(name)
        }
        return try image(from: source, at: index, maxPixelSize: maxPixelSize,
                         applyOrientation: applyOrientation, name: name)
    }

    /// The shared body of both `image` overloads.
    static func image(from source: CGImageSource, at index: Int, maxPixelSize: Int?,
                      applyOrientation: Bool, name: URL) throws -> CGImage {
        guard index < CGImageSourceGetCount(source) else {
            throw ImageForgeError.noImage(name)
        }

        var options: [CFString: Any] = [
            kCGImageSourceShouldCache: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: applyOrientation,
        ]
        if let maxPixelSize {
            options[kCGImageSourceThumbnailMaxPixelSize] = max(1, maxPixelSize)
        }

        if let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) {
            return image
        }
        // Some formats decline the thumbnail path. Fall back to a plain
        // decode, which means the caller may still need to bake orientation.
        guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
            throw ImageForgeError.noImage(name)
        }
        guard applyOrientation else { return image }
        let orientation = properties(of: source, at: index)[kCGImagePropertyOrientation as String] as? Int ?? 1
        return try Pipeline.apply(Orientation.operations(for: orientation), to: image)
    }

    // MARK: - Frames

    /// Every frame of an animation, with the time each is held for.
    ///
    /// A still image comes back as a single frame of one tenth of a second,
    /// so a caller need not special-case it.
    ///
    /// - Parameters:
    ///   - url: The file to read.
    ///   - maxPixelSize: Decode no frame larger than this on the longest side.
    /// - Returns: The frames, in order.
    /// - Throws: ``ImageForgeError/unreadable(_:)`` or ``ImageForgeError/noImage(_:)``.
    public static func frames(at url: URL, maxPixelSize: Int? = nil) throws -> [ImageFrame] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageForgeError.unreadable(url)
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw ImageForgeError.noImage(url) }

        let typeIdentifier = (CGImageSourceGetType(source) as String?) ?? ""
        let keys = ImageFormat.named(typeIdentifier: typeIdentifier).flatMap(AnimationKeys.of)

        return try (0..<count).map { index in
            let image = try image(from: source, at: index, maxPixelSize: maxPixelSize,
                                  applyOrientation: true, name: url)
            let duration = keys?.duration(from: properties(of: source, at: index)) ?? 0.1
            return ImageFrame(image: image, duration: duration)
        }
    }

    // MARK: - Properties

    /// One frame's property dictionary, or an empty one.
    ///
    /// - Parameters:
    ///   - source: The image source.
    ///   - index: The frame.
    /// - Returns: The properties, keyed by their ImageIO names.
    public static func properties(of source: CGImageSource, at index: Int) -> [String: Any] {
        CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any] ?? [:]
    }

    /// A file's property dictionary, without decoding it.
    ///
    /// - Parameter url: The file to read.
    /// - Returns: The properties, or an empty dictionary if it cannot be read.
    public static func properties(of url: URL) -> [String: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return properties(of: source, at: 0)
    }

    /// Whether a source carries an HDR gain map.
    ///
    /// Both spellings are checked: Apple's original gain map and the ISO
    /// one that newer files use.
    ///
    /// - Parameter source: The image source.
    /// - Returns: True when a gain map is present.
    public static func hasGainMap(_ source: CGImageSource) -> Bool {
        let types = [kCGImageAuxiliaryDataTypeHDRGainMap, kCGImageAuxiliaryDataTypeISOGainMap]
        return types.contains {
            CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, $0) != nil
        }
    }
}
