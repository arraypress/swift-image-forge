//
//  CollageGeometry.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Turned rectangles and whether they touch — enough geometry to prove a
//  scattered layout keeps what must stay visible, visible.
//

import CoreGraphics
import Foundation

/// Plane geometry for collage layouts.
enum CollageGeometry {

    /// A rectangle's corners after a clockwise turn about another
    /// rectangle's centre, in top-left origin coordinates — the turn
    /// ``CollageRenderer`` applies to a print.
    ///
    /// - Parameters:
    ///   - rect: The rectangle to turn.
    ///   - degrees: The clockwise turn.
    ///   - pivot: Whose centre it turns about.
    /// - Returns: Four corners, in order around the outline.
    static func corners(of rect: CGRect, turnedBy degrees: Double, about pivot: CGRect) -> [CGPoint] {
        let angle = degrees * .pi / 180, cosA = cos(angle), sinA = sin(angle)
        let cx = Double(pivot.midX), cy = Double(pivot.midY)
        let points = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                      CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        return points.map { p in
            let dx = Double(p.x) - cx, dy = Double(p.y) - cy
            return CGPoint(x: cx + dx * cosA - dy * sinA, y: cy + dx * sinA + dy * cosA)
        }
    }

    /// Whether two convex polygons share any area, by the separating-axis
    /// test: they are apart exactly when some edge's normal separates their
    /// projections. Touching edges do not count as overlap.
    static func convexPolygonsOverlap(_ a: [CGPoint], _ b: [CGPoint]) -> Bool {
        for polygon in [a, b] {
            for i in polygon.indices {
                let p = polygon[i], q = polygon[(i + 1) % polygon.count]
                let axis = (x: Double(q.y - p.y), y: Double(p.x - q.x))
                let pa = a.map { Double($0.x) * axis.x + Double($0.y) * axis.y }
                let pb = b.map { Double($0.x) * axis.x + Double($0.y) * axis.y }
                if pa.max()! <= pb.min()! || pb.max()! <= pa.min()! { return false }
            }
        }
        return true
    }
}
