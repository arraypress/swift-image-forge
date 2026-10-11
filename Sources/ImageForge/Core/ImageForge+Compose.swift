//
//  ImageForge+Compose.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation

public extension ImageForge {

    /// Draws layers — each with an optional stroke, shadow and glow — onto
    /// a backdrop.
    ///
    /// Float and premultiplied throughout: soft edges keep no dark fringe,
    /// transparent canvas stays transparent, and an HDR or 16-bit input
    /// gives a half-float result.
    ///
    /// - Parameter composition: The backdrop, canvas size and layers.
    /// - Returns: The picture.
    /// - Throws: ``ImageForgeError/emptyResult(_:)`` for a composition that
    ///   cannot be drawn — no canvas to derive, a `.smart` anchor, a canvas
    ///   over 32768 px a side — or a render that fails.
    static func compose(_ composition: Composition) throws -> CGImage {
        try LayerRenderer.render(composition)
    }

    /// Draws a composition and writes it.
    ///
    /// - Parameters:
    ///   - composition: What to draw.
    ///   - destination: Where to write it.
    ///   - encode: Format, quality and the rest. With no format, the
    ///     destination's extension decides, then PNG. A format that cannot
    ///     hold transparency is flattened onto ``EncodeSpec/matte``.
    ///   - overwrites: Whether an existing file may be replaced.
    /// - Returns: The number of bytes written.
    /// - Throws: ``ImageForgeError/destinationExists(_:)`` and the rest.
    @discardableResult
    static func compose(_ composition: Composition, to destination: URL,
                        encode: EncodeSpec = EncodeSpec(), overwrites: Bool = false) throws -> Int {
        if FileManager.default.fileExists(atPath: destination.path) && !overwrites {
            throw ImageForgeError.destinationExists(destination)
        }
        let format = encode.format ?? ImageFormat.named(fileExtension: destination.pathExtension) ?? .png
        var picture = try compose(composition)
        if picture.hasAlphaChannel && !format.supportsAlpha {
            picture = try Renderer.flatten(picture, onto: encode.matte)
        }
        let data = try ImageEncoder.encode(picture, format: format, spec: encode)
        return try ImageEncoder.write(data, to: destination, overwrites: overwrites)
    }
}
