//
//  Backdrop.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import CoreGraphics
import Foundation

/// What a composition is drawn onto.
public enum Backdrop: Sendable {
    /// Nothing: the result keeps transparency wherever no layer is.
    case clear
    /// A solid colour.
    case color(ForgeColor)
    /// A picture, scaled to cover the canvas and centred — cropped rather
    /// than stretched when the shapes differ.
    case image(CGImage)
}
