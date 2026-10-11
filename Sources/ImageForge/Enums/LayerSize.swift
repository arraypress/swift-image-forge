//
//  LayerSize.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// How large a layer is drawn on the canvas. The aspect ratio is always kept.
public enum LayerSize: Sendable, Codable, Equatable, Hashable {
    /// The layer's own pixel size.
    case original
    /// Its own size times a factor.
    case scale(Double)
    /// As large as fits inside this share of the canvas, from 0 to 1 —
    /// `0.8` is "80% of the canvas in whichever direction runs out first".
    case fit(Double)
    /// This many pixels wide.
    case width(Double)
    /// This many pixels tall.
    case height(Double)
}
