//
//  CollageCell.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Where one photo landed in a collage, and which part of it is showing.
//

import CoreGraphics
import Foundation

/// One photo's place in a collage.
public struct CollageCell: Sendable, Codable, Equatable {
    /// Which photo, as its position in the list given (counting from 0).
    public let source: Int
    /// The cell, in top-left origin pixels of the canvas. For a polaroid
    /// this is the print, frame included, before it is turned.
    public let rect: CGRect
    /// The photo's own area inside the cell — smaller than `rect` only for
    /// a framed print.
    public let photoRect: CGRect
    /// How far the cell is turned about its centre, in degrees, clockwise.
    public let rotation: Double
    /// The part of the source shown, in its top-left origin pixels; nil
    /// when the whole photo is shown.
    public let crop: CGRect?
    /// What the crop was centred on, when something was found.
    public let focus: SubjectKind?
    /// For a diagonal split, the cell's outline in canvas pixels.
    public let outline: [CGPoint]?

    /// - Parameters:
    ///   - source: Which photo, counting from 0.
    ///   - rect: The cell, in canvas pixels.
    ///   - photoRect: The photo's area inside the cell.
    ///   - rotation: Clockwise turn, in degrees.
    ///   - crop: The part of the source shown.
    ///   - focus: What the crop was centred on.
    ///   - outline: A non-rectangular outline, for a diagonal split.
    public init(source: Int, rect: CGRect, photoRect: CGRect, rotation: Double = 0,
                crop: CGRect? = nil, focus: SubjectKind? = nil, outline: [CGPoint]? = nil) {
        self.source = source
        self.rect = rect
        self.photoRect = photoRect
        self.rotation = rotation
        self.crop = crop
        self.focus = focus
        self.outline = outline
    }
}
