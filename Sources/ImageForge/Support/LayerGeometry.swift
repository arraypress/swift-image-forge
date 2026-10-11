//
//  LayerGeometry.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Where layers land and how far their effects reach — the sums of a
//  composition, in top-left origin canvas pixels, kept apart from the
//  pixels so they can be tested against known numbers.
//

import CoreGraphics
import Foundation

/// Placement and effect-reach arithmetic for compositions.
public enum LayerGeometry {

    /// The size a layer is drawn at, in whole pixels (at least 1×1).
    ///
    /// - Parameters:
    ///   - natural: The layer's own pixel size.
    ///   - size: How it is to be sized.
    ///   - canvas: The canvas; nil when it is still being derived, in which
    ///     case ``LayerSize/fit(_:)`` has nothing to fit and draws at the
    ///     layer's own size.
    /// - Returns: The drawn size.
    public static func drawnSize(of natural: CGSize, as size: LayerSize, canvas: CGSize?) -> CGSize {
        let width = max(natural.width, 1), height = max(natural.height, 1)
        let factor: CGFloat
        switch size {
        case .original:
            factor = 1
        case .scale(let value):
            factor = CGFloat(value)
        case .fit(let share):
            guard let canvas else { factor = 1; break }
            let wide: CGFloat = canvas.width * CGFloat(share) / width
            let tall: CGFloat = canvas.height * CGFloat(share) / height
            factor = min(wide, tall)
        case .width(let pixels):
            factor = CGFloat(pixels) / width
        case .height(let pixels):
            factor = CGFloat(pixels) / height
        }
        let drawnWidth: CGFloat = max(1, (width * factor).rounded())
        let drawnHeight: CGFloat = max(1, (height * factor).rounded())
        return CGSize(width: drawnWidth, height: drawnHeight)
    }

    /// Where a layer's top-left corner lands, snapped to a whole pixel.
    ///
    /// - Parameters:
    ///   - drawn: The layer's drawn size.
    ///   - placement: Its anchor, inset or explicit position.
    ///   - canvas: The canvas size.
    /// - Returns: The top-left corner, top-left origin.
    public static func origin(of drawn: CGSize, placement: LayerPlacement, canvas: CGSize) -> CGPoint {
        if let position = placement.position {
            let x: CGFloat = position.x.resolved(along: canvas.width)
            let y: CGFloat = position.y.resolved(along: canvas.height)
            return CGPoint(x: x.rounded(), y: y.rounded())
        }
        let biasX: CGFloat = placement.anchor.horizontalBias ?? 0.5
        let biasY: CGFloat = placement.anchor.verticalBias ?? 0.5
        // An inset pushes away from a pinned edge; on a centred axis it has
        // no edge to push from.
        let insetX: CGFloat = biasX == 0.5 ? 0 : placement.inset.resolved(along: canvas.width)
        let insetY: CGFloat = biasY == 0.5 ? 0 : placement.inset.resolved(along: canvas.height)
        let x: CGFloat = insetX + biasX * (canvas.width - drawn.width - 2 * insetX)
        let y: CGFloat = insetY + biasY * (canvas.height - drawn.height - 2 * insetY)
        return CGPoint(x: x.rounded(), y: y.rounded())
    }

    /// The rectangle a layer and all its effects cover, top-left origin.
    ///
    /// The stroke reaches its width past the edge; a glow its radius; a
    /// shadow its blur, from wherever its offset puts it.
    ///
    /// - Parameters:
    ///   - rect: The layer's own rectangle.
    ///   - effects: Its effects.
    /// - Returns: The covered rectangle, grown to whole pixels.
    public static func reach(of rect: CGRect, effects: LayerEffects) -> CGRect {
        var covered = rect
        if let stroke = effects.stroke, stroke.width > 0 {
            covered = covered.union(rect.insetBy(dx: -CGFloat(stroke.width), dy: -CGFloat(stroke.width)))
        }
        if let glow = effects.glow, glow.radius > 0 {
            covered = covered.union(rect.insetBy(dx: -CGFloat(glow.radius), dy: -CGFloat(glow.radius)))
        }
        if let shadow = effects.shadow {
            let cast = rect.offsetBy(dx: CGFloat(shadow.offsetX), dy: CGFloat(shadow.offsetY))
            covered = covered.union(cast.insetBy(dx: -CGFloat(shadow.blur), dy: -CGFloat(shadow.blur)))
        }
        return covered.integral
    }

    /// The Gaussian σ for a softening distance: the effect has faded to
    /// nothing `distance` pixels past a hard edge. Core Image's blur radius
    /// is σ (measured within 4% from 3 to 24 px).
    static func sigma(forSoftening distance: Double) -> Double { max(0, distance) / 3 }

    /// The scale that makes `source` cover `canvas`, and the offset that
    /// centres it — a backdrop image cropped, never stretched.
    static func cover(_ source: CGSize, canvas: CGSize) -> (scale: CGFloat, offset: CGPoint) {
        let scale: CGFloat = max(canvas.width / max(source.width, 1), canvas.height / max(source.height, 1))
        let offset = CGPoint(x: (canvas.width - source.width * scale) / 2,
                             y: (canvas.height - source.height * scale) / 2)
        return (scale, offset)
    }
}
