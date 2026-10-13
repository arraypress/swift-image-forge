//
//  CollageRenderer.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  The pixels of a collage, in Core Graphics. The planner has already
//  decided where everything goes; this draws it: the background, each photo
//  clipped to its cell (rounded, or slanted for a diagonal split), the
//  polaroid's frame and shadow, and the captions.
//
//  Coordinates are top-left throughout, matching the planner and every other
//  rectangle this library reports. The context is flipped once, and each
//  image and line of text is flipped back locally where it is drawn —
//  otherwise every photo comes out upside down.
//
//  Text colour is set on the attributed string, not the context:
//  CTLineDraw ignores the context's fill colour.
//

import CoreGraphics
import CoreText
import Foundation

/// Draws collages.
enum CollageRenderer {

    /// One photo, ready to draw.
    struct Piece {
        /// The decoded photo.
        let image: CGImage
        /// The caption, when captions are on.
        let caption: String?
        /// The part to show, in the photo's top-left pixels; nil for all.
        let crop: CGRect?
    }

    /// Draws a planned collage.
    ///
    /// - Parameters:
    ///   - slots: Where each photo goes, in drawing order.
    ///   - pieces: The photos, indexed by each slot's `index`.
    ///   - spec: The collage.
    ///   - backdrop: The background picture, when there is one.
    /// - Returns: The canvas.
    /// - Throws: ``ImageForgeError/emptyResult(_:)`` if no context could be made.
    static func render(_ slots: [CollagePlanner.Slot], pieces: [Piece], spec: CollageSpec,
                       backdrop: CGImage?) throws -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: spec.width, height: spec.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ImageForgeError.emptyResult("a \(spec.width)×\(spec.height) collage")
        }
        let canvas = CGRect(x: 0, y: 0, width: spec.width, height: spec.height)
        context.interpolationQuality = .high
        // Top-left origin from here on.
        context.translateBy(x: 0, y: CGFloat(spec.height))
        context.scaleBy(x: 1, y: -1)

        switch spec.background {
        case .color(let color):
            context.setFillColor(color.cgColor)
            context.fill(canvas)
        case .image:
            if let backdrop {
                let crop = CollagePlanner.crop(backdrop.pixelSize, aspect: Double(spec.width) / Double(spec.height),
                                               focus: nil)
                if let cropped = backdrop.cropping(to: crop) { draw(cropped, in: canvas, context) }
            }
        }

        let polaroid = spec.layout == .polaroid
        let longSide = CGFloat(max(spec.width, spec.height))
        for slot in slots {
            let piece = pieces[slot.index]
            context.saveGState()
            if slot.rotation != 0 {
                context.translateBy(x: slot.rect.midX, y: slot.rect.midY)
                context.rotate(by: CGFloat(slot.rotation * .pi / 180))
                context.translateBy(x: -slot.rect.midX, y: -slot.rect.midY)
            }
            if polaroid {
                // The print: a soft shadow under white card. Shadow offsets
                // live in the unflipped base space, where down is negative.
                context.saveGState()
                context.setShadow(offset: CGSize(width: 0, height: -longSide * 0.004), blur: longSide * 0.012,
                                  color: CGColor(gray: 0, alpha: 0.35))
                context.setFillColor(CGColor(gray: 0.98, alpha: 1))
                context.addPath(shape(slot.rect, radius: CGFloat(spec.radius)))
                context.fillPath()
                context.restoreGState()
            }
            context.saveGState()
            if let outline = slot.outline {
                context.addLines(between: outline)
                context.closePath()
            } else {
                context.addPath(shape(slot.photo, radius: polaroid ? 0 : CGFloat(spec.radius)))
            }
            context.clip()
            drawPhoto(piece, in: slot.photo, fit: spec.fit, context)
            context.restoreGState()

            if let caption = piece.caption, !caption.isEmpty {
                if polaroid {
                    // Only the middle of the border: a neighbour may lie over its ends.
                    let zone = CollagePlanner.captionZone(of: slot)
                    drawText(caption, centredIn: zone, size: zone.height * 0.3,
                             color: CGColor(gray: 0.2, alpha: 1), shadow: false, context)
                } else {
                    let size = max(12, min(slot.photo.height * 0.06, longSide * 0.022))
                    let band = CGRect(x: slot.photo.minX + size * 0.8, y: slot.photo.maxY - size * 2.2,
                                      width: slot.photo.width - size * 1.6, height: size * 1.6)
                    drawText(caption, leadingIn: band, size: size, color: CGColor(gray: 1, alpha: 1),
                             shadow: true, context)
                }
            }
            context.restoreGState()
        }

        guard let image = context.makeImage() else {
            throw ImageForgeError.emptyResult("a \(spec.width)×\(spec.height) collage")
        }
        return image
    }

    /// A rectangle, rounded when there is a radius.
    static func shape(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let r = min(radius, min(rect.width, rect.height) / 2)
        return r > 0 ? CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
                     : CGPath(rect: rect, transform: nil)
    }

    /// A photo into its area: cropped to cover it, or whole inside it.
    static func drawPhoto(_ piece: Piece, in area: CGRect, fit: CollageFit, _ context: CGContext) {
        switch fit {
        case .fill:
            let source = piece.crop.flatMap { piece.image.cropping(to: $0) } ?? piece.image
            draw(source, in: area, context)
        case .fit:
            let size = piece.image.pixelSize
            let scale = min(area.width / size.width, area.height / size.height)
            let w = size.width * scale, h = size.height * scale
            draw(piece.image, in: CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h), context)
        }
    }

    /// Draws an image the right way up in a top-left-origin context.
    static func draw(_ image: CGImage, in rect: CGRect, _ context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    /// One line of text, centred in a band.
    static func drawText(_ text: String, centredIn band: CGRect, size: CGFloat, color: CGColor,
                         shadow: Bool, _ context: CGContext) {
        guard let line = line(text, size: size, color: color, width: band.width) else { return }
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        place(line, at: CGPoint(x: band.midX - CGFloat(width) / 2, y: band.midY + size * 0.35),
              shadow: shadow, context)
    }

    /// One line of text, from the left of a band.
    static func drawText(_ text: String, leadingIn band: CGRect, size: CGFloat, color: CGColor,
                         shadow: Bool, _ context: CGContext) {
        guard let line = line(text, size: size, color: color, width: band.width) else { return }
        place(line, at: CGPoint(x: band.minX, y: band.midY + size * 0.35), shadow: shadow, context)
    }

    /// A line of text in the system font, cut short with an ellipsis when
    /// it would not fit.
    static func line(_ text: String, size: CGFloat, color: CGColor, width: CGFloat) -> CTLine? {
        guard let font = CTFontCreateUIFontForLanguage(.system, size, nil) else { return nil }
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let full = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        guard CTLineGetTypographicBounds(full, nil, nil, nil) > Double(width) else { return full }
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        return CTLineCreateTruncatedLine(full, Double(width), .end, ellipsis) ?? full
    }

    /// Draws a line with its baseline at a top-left point.
    static func place(_ line: CTLine, at baseline: CGPoint, shadow: Bool, _ context: CGContext) {
        context.saveGState()
        if shadow {
            context.setShadow(offset: CGSize(width: 0, height: -1), blur: 4, color: CGColor(gray: 0, alpha: 0.7))
        }
        context.translateBy(x: baseline.x, y: baseline.y)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
