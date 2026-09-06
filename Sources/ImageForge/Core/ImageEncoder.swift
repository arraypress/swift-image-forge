//
//  ImageEncoder.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Writing, by two roads.
//
//  The **render** road is the obvious one: a `CGImage` goes to a
//  destination. It can express anything, and it loses the auxiliary data a
//  `CGImage` cannot hold — depth maps, portrait mattes, and the HDR gain
//  map that makes a modern phone photo look right on a bright display.
//
//  The **passthrough** road hands the source straight to the destination
//  with `CGImageDestinationAddImageFromSource`, which carries all of that
//  through. It can only do what ImageIO itself can do on the way past — a
//  format change, a re-encode, a downscale — so the pipeline uses it when
//  the job fits and falls back to rendering when it does not.
//

import CoreGraphics
import Foundation
import ImageIO

/// Writes images.
public enum ImageEncoder {

    // MARK: - Render path

    /// Encodes an image to data.
    ///
    /// - Parameters:
    ///   - image: The pixels to write.
    ///   - format: The container to write.
    ///   - spec: Quality, metadata policy and the rest.
    ///   - sourceProperties: The source's properties, for the metadata
    ///     policy to filter. Nil writes no metadata at all.
    /// - Returns: The encoded bytes.
    /// - Throws: ``ImageForgeError/formatNotWritable(_:alternative:)`` or
    ///   ``ImageForgeError/encodingFailed(_:reason:)``.
    public static func encode(_ image: CGImage, format: ImageFormat, spec: EncodeSpec,
                              sourceProperties: [String: Any]? = nil) throws -> Data {
        try FormatSupport.requireWritable(format)

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, format.typeIdentifier as CFString, 1, nil) else {
            throw ImageForgeError.encodingFailed(format, reason: "no encoder for \(format.typeIdentifier)")
        }

        var properties = Metadata.filtered(sourceProperties ?? [:], policy: spec.metadata)
        applyDestinationOptions(&properties, format: format, spec: spec)
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageForgeError.encodingFailed(format, reason: "the encoder rejected the image")
        }
        return data as Data
    }

    /// Encodes an animation to data.
    ///
    /// - Parameters:
    ///   - frames: The frames, in order.
    ///   - format: The container. Must hold animation.
    ///   - spec: Quality, metadata policy and the rest.
    ///   - animation: Loop count and frame timing.
    /// - Returns: The encoded bytes.
    /// - Throws: ``ImageForgeError/notAnimatable(_:)`` when the format holds
    ///   no frames, or ``ImageForgeError/encodingFailed(_:reason:)``.
    public static func encode(frames: [ImageFrame], format: ImageFormat, spec: EncodeSpec,
                              animation: AnimationSpec) throws -> Data {
        try FormatSupport.requireWritable(format)
        guard let keys = AnimationKeys.of(format) else {
            throw ImageForgeError.notAnimatable(format)
        }
        guard !frames.isEmpty else {
            throw ImageForgeError.emptyResult("an animation with no frames")
        }

        let ordered = arrange(frames, with: animation)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, format.typeIdentifier as CFString, ordered.count, nil) else {
            throw ImageForgeError.encodingFailed(format, reason: "no encoder for \(format.typeIdentifier)")
        }

        CGImageDestinationSetProperties(destination,
                                        keys.imageProperties(loops: animation.loopCount) as CFDictionary)
        for frame in ordered {
            let duration = animation.frameDuration ?? frame.duration
            var properties = keys.frameProperties(duration: duration)
            applyDestinationOptions(&properties, format: format, spec: spec)
            CGImageDestinationAddImage(destination, frame.image, properties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw ImageForgeError.encodingFailed(format, reason: "the encoder rejected the animation")
        }
        return data as Data
    }

    /// Puts frames in the order an ``AnimationSpec`` asks for.
    ///
    /// - Parameters:
    ///   - frames: The frames as decoded.
    ///   - spec: The stride, reversal and ping-pong to apply.
    /// - Returns: The frames to write.
    static func arrange(_ frames: [ImageFrame], with spec: AnimationSpec) -> [ImageFrame] {
        var result = spec.frameStride > 1
            ? frames.enumerated().filter { $0.offset % spec.frameStride == 0 }.map(\.element)
            : frames
        if result.isEmpty { result = Array(frames.prefix(1)) }
        if spec.reversed { result.reverse() }
        if spec.pingPong, result.count > 2 {
            result += result.dropFirst().dropLast().reversed()
        }
        return result
    }

    // MARK: - Passthrough path

    /// Copies an image from a source to a destination without ever building
    /// a `CGImage`, so auxiliary data — depth, mattes, the HDR gain map —
    /// travels with it.
    ///
    /// - Parameters:
    ///   - source: The source to copy from.
    ///   - format: The container to write.
    ///   - spec: Quality, metadata and HDR policy.
    ///   - maxPixelSize: Downscale to this longest side on the way past.
    ///     The gain map is scaled with the image.
    ///   - sourceProperties: The source's properties, for the metadata policy.
    /// - Returns: The encoded bytes.
    /// - Throws: ``ImageForgeError/encodingFailed(_:reason:)``.
    public static func passthrough(from source: CGImageSource, format: ImageFormat,
                                   spec: EncodeSpec, maxPixelSize: Int?,
                                   sourceProperties: [String: Any]) throws -> Data {
        try FormatSupport.requireWritable(format)

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, format.typeIdentifier as CFString, 1, nil) else {
            throw ImageForgeError.encodingFailed(format, reason: "no encoder for \(format.typeIdentifier)")
        }

        // The pixels are not being redrawn, so whatever orientation the
        // source stored them at still applies — resetting it to 1 here would
        // lay every sideways photo on its side.
        let orientation = sourceProperties[kCGImagePropertyOrientation as String] as? Int ?? 1
        var properties = Metadata.filtered(sourceProperties, policy: spec.metadata,
                                           orientation: orientation)
        applyDestinationOptions(&properties, format: format, spec: spec)

        if let maxPixelSize {
            properties[kCGImageDestinationImageMaxPixelSize as String] = max(1, maxPixelSize)
        }
        switch spec.hdr {
        case .preserve:
            properties[kCGImageDestinationPreserveGainMap as String] = true
        case .tonemap:
            properties[kCGImageDestinationPreserveGainMap as String] = false
            properties[kCGImageDestinationEncodeRequest as String] = kCGImageDestinationEncodeToSDR
        case .discard:
            properties[kCGImageDestinationPreserveGainMap as String] = false
        }

        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageForgeError.encodingFailed(format, reason: "the encoder rejected the source")
        }
        return data as Data
    }

    // MARK: - Icons

    /// Writes several sizes of one image into an icon container.
    ///
    /// - Parameters:
    ///   - image: The source image. Cropped to a square first if it is not one.
    ///   - format: `.icns` or `.ico`.
    ///   - spec: The sizes to render and the background behind transparency.
    /// - Returns: The encoded bytes.
    /// - Throws: ``ImageForgeError/encodingFailed(_:reason:)`` when the
    ///   format is not an icon container.
    public static func encodeIcon(_ image: CGImage, format: ImageFormat,
                                  spec: IconSpec) throws -> Data {
        guard format.isIconContainer else {
            throw ImageForgeError.encodingFailed(format, reason: "not an icon container")
        }
        try FormatSupport.requireWritable(format)
        guard !spec.sizes.isEmpty else {
            throw ImageForgeError.emptyResult("an icon with no sizes")
        }
        // Checked up front: an unsupported size is accepted by
        // `CGImageDestinationAddImage` and only rejected at finalise, by
        // which point the whole file is lost rather than the one size.
        let supported = IconSizes.supported(for: format) ?? []
        if let bad = spec.sizes.first(where: { !supported.contains($0) }) {
            throw ImageForgeError.iconSizeUnsupported(format, size: bad, supported: supported)
        }

        var square = image
        if image.width != image.height {
            let rect = try Geometry.cropRect(for: .square(), in: image.pixelSize)
            square = try Renderer.crop(image, to: rect)
        }
        if spec.background.alpha > 0 {
            square = try Renderer.flatten(square, onto: spec.background)
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, format.typeIdentifier as CFString, spec.sizes.count, nil) else {
            throw ImageForgeError.encodingFailed(format, reason: "no encoder for \(format.typeIdentifier)")
        }
        for side in spec.sizes {
            let scaled = try Renderer.scale(square, to: CGSize(width: side, height: side))
            CGImageDestinationAddImage(destination, scaled, nil)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw ImageForgeError.encodingFailed(format, reason: "the encoder rejected the icon")
        }
        return data as Data
    }

    // MARK: - Files

    /// Writes bytes to a file, refusing to replace one unless asked.
    ///
    /// - Parameters:
    ///   - data: The bytes to write.
    ///   - url: Where to write them.
    ///   - overwrites: Whether an existing file may be replaced.
    /// - Returns: The number of bytes written.
    /// - Throws: ``ImageForgeError/destinationExists(_:)`` or
    ///   ``ImageForgeError/writeFailed(_:reason:)``.
    @discardableResult
    public static func write(_ data: Data, to url: URL, overwrites: Bool) throws -> Int {
        if FileManager.default.fileExists(atPath: url.path) && !overwrites {
            throw ImageForgeError.destinationExists(url)
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw ImageForgeError.writeFailed(url, reason: error.localizedDescription)
        }
        return data.count
    }

    // MARK: - Options

    /// Adds the encoder settings a spec asks for to a properties dictionary.
    ///
    /// - Parameters:
    ///   - properties: The dictionary to add to.
    ///   - format: The format being written; quality is dropped for lossless ones.
    ///   - spec: The settings to apply.
    static func applyDestinationOptions(_ properties: inout [String: Any],
                                        format: ImageFormat, spec: EncodeSpec) {
        if format.isLossy {
            properties[kCGImageDestinationLossyCompressionQuality as String] = spec.quality
        }
        if spec.optimizeForSharing {
            properties[kCGImageDestinationOptimizeColorForSharing as String] = true
        }
    }
}
