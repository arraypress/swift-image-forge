//
//  DocumentTone.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  What a scanner's "colour / greyscale / black and white" switch does, as
//  data. The one tonal step in a library that otherwise leaves colour to
//  VideoGrade: evening out a photographed page is part of turning it into a
//  document, the way flattening transparency is part of turning a PNG into
//  a JPEG — not a look anyone chooses.
//

import Foundation

/// How a photographed page is cleaned up.
public enum DocumentTone: String, CaseIterable, Sendable, Codable, Hashable {
    /// Shadows and paper tint evened out, colour kept — stamps, signatures
    /// in blue ink and highlighter all survive. The default.
    case color
    /// Evened out, then the colour taken away. Smaller, and what most
    /// paperwork needs.
    case gray
    /// Every pixel ink or paper. The smallest, the most legible on a clean
    /// printout, and the one that loses a pale signature — so never the
    /// default.
    case blackAndWhite
}
