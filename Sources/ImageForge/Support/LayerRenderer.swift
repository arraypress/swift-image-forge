//
//  LayerRenderer.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  The pixels of a composition, in Core Image: float, linear, premultiplied
//  throughout, so a soft edge composited onto white keeps no dark fringe and
//  values above 1 survive to an HDR-capable output.
//
//  Effects follow Photoshop's layer styles for what they mean (stroke
//  outside the edge, shadow by offset and softness, glow around the edge);
//  the arithmetic is Core Image's. Every effect starts from the layer's
//  silhouette in its colour — `CISourceIn` against the layer, which keeps
//  the colour colour-managed. CIColorMatrix biases would set it in the
//  linear working space, turning sRGB 0.5 grey into 0.73.
//

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Draws a ``Composition``.
enum LayerRenderer {

    /// Renders a composition to a `CGImage`.
    static func render(_ composition: Composition) throws -> CGImage {
        let plan = try layout(composition)
        let canvas = plan.canvas
        let extent = CGRect(origin: .zero, size: canvas)

        var picture = backdrop(composition.backdrop, canvas: canvas)
        for (layer, frame) in zip(composition.layers, plan.frames) {
            picture = draw(layer, in: frame, canvasHeight: canvas.height).composited(over: picture)
        }
        picture = picture.cropped(to: extent)

        let output = outputFormat(for: composition)
        let context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB) as Any,
        ])
        guard let rendered = context.createCGImage(picture, from: extent,
                                                   format: output.format, colorSpace: output.space) else {
            throw ImageForgeError.emptyResult("a \(Int(canvas.width))×\(Int(canvas.height)) composition")
        }
        // An opaque backdrop makes an opaque picture; say so, or every PNG of
        // it carries an alpha channel that is 1 everywhere. Deep output keeps
        // its channel — the flatten is 8-bit.
        if output.format == .RGBA8, composition.backdrop.isOpaque {
            return try Renderer.flatten(rendered, onto: .white)
        }
        return rendered
    }

    // MARK: - Layout

    /// The canvas and each layer's frame, top-left origin.
    struct Plan {
        let canvas: CGSize
        let frames: [CGRect]
    }

    /// Works out the canvas and where every layer goes, refusing what
    /// cannot be drawn.
    static func layout(_ composition: Composition) throws -> Plan {
        if composition.layers.contains(where: { $0.style.placement.anchor == .smart }) {
            throw ImageForgeError.emptyResult("a layer anchored .smart (compositions take fixed anchors)")
        }
        var canvas: CGSize
        var firstOrigin: CGPoint? = nil
        if let size = composition.size {
            canvas = size
        } else if case .image(let image) = composition.backdrop {
            canvas = image.pixelSize
        } else if let first = composition.layers.first {
            // No canvas named: fit the first layer and everything it casts.
            let drawn = LayerGeometry.drawnSize(of: first.image.pixelSize, as: first.style.placement.size, canvas: nil)
            let reach = LayerGeometry.reach(of: CGRect(origin: .zero, size: drawn), effects: first.style.effects)
            canvas = reach.size
            firstOrigin = CGPoint(x: -reach.minX, y: -reach.minY)
        } else {
            throw ImageForgeError.emptyResult("a composition with no layers, no backdrop image and no size")
        }
        canvas = CGSize(width: canvas.width.rounded(), height: canvas.height.rounded())
        guard canvas.width >= 1, canvas.height >= 1, canvas.width <= 32_768, canvas.height <= 32_768 else {
            throw ImageForgeError.emptyResult("a \(Int(canvas.width))×\(Int(canvas.height)) canvas (1…32768 a side)")
        }
        var frames: [CGRect] = []
        for (index, layer) in composition.layers.enumerated() {
            let drawn = LayerGeometry.drawnSize(of: layer.image.pixelSize, as: layer.style.placement.size, canvas: canvas)
            let origin = index == 0 ? (firstOrigin ?? LayerGeometry.origin(of: drawn, placement: layer.style.placement, canvas: canvas))
                                    : LayerGeometry.origin(of: drawn, placement: layer.style.placement, canvas: canvas)
            frames.append(CGRect(origin: origin, size: drawn))
        }
        return Plan(canvas: canvas, frames: frames)
    }

    // MARK: - Drawing

    /// The backdrop filling the canvas.
    static func backdrop(_ backdrop: Backdrop, canvas: CGSize) -> CIImage {
        let extent = CGRect(origin: .zero, size: canvas)
        switch backdrop {
        case .clear:
            return CIImage(color: .clear).cropped(to: extent)
        case .color(let color):
            return CIImage(color: CIColor(cgColor: color.cgColor)).cropped(to: extent)
        case .image(let image):
            let cover = LayerGeometry.cover(image.pixelSize, canvas: canvas)
            let scaled: CIImage = CIImage(cgImage: image)
                .transformed(by: CGAffineTransform(scaleX: cover.scale, y: cover.scale), highQualityDownsample: true)
            // Centred, so the offset is the same measured from either edge.
            let placed: CIImage = scaled.transformed(by: CGAffineTransform(translationX: cover.offset.x, y: cover.offset.y))
            return placed.cropped(to: extent)
                .composited(over: CIImage(color: .clear).cropped(to: extent))
        }
    }

    /// One layer and its effects, placed, ready to go over what is beneath.
    static func draw(_ layer: CompositeLayer, in frame: CGRect, canvasHeight: CGFloat) -> CIImage {
        let natural = layer.image.pixelSize
        var image = CIImage(cgImage: layer.image)
        if frame.size != natural {
            let scale = CGAffineTransform(scaleX: frame.width / max(natural.width, 1),
                                          y: frame.height / max(natural.height, 1))
            image = image.transformed(by: scale, highQualityDownsample: true)
        }
        // Core Image counts up from the bottom; the frame counts down.
        let bottom: CGFloat = canvasHeight - frame.maxY
        image = image.transformed(by: CGAffineTransform(translationX: frame.minX - image.extent.minX,
                                                        y: bottom - image.extent.minY))
        let opacity = min(1, max(0, layer.style.opacity))
        if opacity < 1 { image = faded(image, by: opacity) }

        let effects = layer.style.effects
        var stack = CIImage.empty()
        if let shadow = effects.shadow, shadow.opacity > 0 {
            var cast = silhouette(of: image, in: shadow.color)
                .transformed(by: CGAffineTransform(translationX: CGFloat(shadow.offsetX), y: -CGFloat(shadow.offsetY)))
            cast = blurred(cast, softening: shadow.blur)
            stack = faded(cast, by: shadow.opacity).composited(over: stack)
        }
        if let glow = effects.glow, glow.opacity > 0, glow.radius > 0 {
            let light = blurred(silhouette(of: image, in: glow.color), softening: glow.radius)
            stack = faded(light, by: glow.opacity).composited(over: stack)
        }
        if let stroke = effects.stroke, stroke.width > 0 {
            let dilate = CIFilter.morphologyMaximum()
            dilate.inputImage = silhouette(of: image, in: stroke.color)
            dilate.radius = Float(stroke.width)
            if let outline = dilate.outputImage { stack = outline.composited(over: stack) }
        }
        return image.composited(over: stack)
    }

    /// The layer's shape filled with a colour: the colour wherever the
    /// layer is, at the layer's alpha times the colour's.
    static func silhouette(of image: CIImage, in color: ForgeColor) -> CIImage {
        let fill = CIImage(color: CIColor(cgColor: color.cgColor)).cropped(to: image.extent)
        let cut = CIFilter.sourceInCompositing()
        cut.inputImage = fill
        cut.backgroundImage = image
        return cut.outputImage ?? image
    }

    /// Softened by a Gaussian that has faded out `distance` px past an edge.
    static func blurred(_ image: CIImage, softening distance: Double) -> CIImage {
        let sigma = LayerGeometry.sigma(forSoftening: distance)
        guard sigma > 0 else { return image }
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image
        blur.radius = Float(sigma)
        return blur.outputImage ?? image
    }

    /// Every channel scaled — premultiplied, so this is opacity. The matrix
    /// unpremultiplies, scales alpha and premultiplies again; with no bias
    /// the transparent area stays transparent.
    static func faded(_ image: CIImage, by amount: Double) -> CIImage {
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(min(1, max(0, amount))))
        return matrix.outputImage ?? image
    }

    // MARK: - Output

    /// 8-bit for 8-bit inputs; half-float when any input is deeper or
    /// extended-range, in that input's colour space, so HDR survives.
    static func outputFormat(for composition: Composition) -> (format: CIFormat, space: CGColorSpace) {
        var images: [CGImage] = composition.layers.map(\.image)
        if case .image(let backdrop) = composition.backdrop { images.insert(backdrop, at: 0) }
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let primary: CGColorSpace = images.first.map(Renderer.usableColorSpace(for:)) ?? srgb
        if let extended = images.first(where: { isExtended($0) }) {
            return (.RGBAh, Renderer.usableColorSpace(for: extended))
        }
        if images.contains(where: { $0.bitsPerComponent > 8 }) {
            return (.RGBAh, primary)
        }
        return (.RGBA8, primary)
    }

    /// Whether an image's values may go past 1: an extended-range or HDR space.
    static func isExtended(_ image: CGImage) -> Bool {
        guard let space = image.colorSpace else { return false }
        return CGColorSpaceUsesExtendedRange(space) || space.isHDR()
    }
}

extension Backdrop {
    /// Whether nothing shows through: a solid colour or a picture with no
    /// transparency.
    var isOpaque: Bool {
        switch self {
        case .clear: return false
        case .color(let color): return color.alpha >= 1
        case .image(let image): return !image.hasAlphaChannel
        }
    }
}
