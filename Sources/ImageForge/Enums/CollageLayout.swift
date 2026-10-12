//
//  CollageLayout.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  The shapes a collage can take, and the small choices that go with them.
//  Each is a plain string in JSON, so a saved collage reads as what it is.
//

import Foundation

/// How the photos of a collage are arranged.
public enum CollageLayout: String, Sendable, Codable, CaseIterable {
    /// Rows and columns of equal cells; a short last row stretches to fill.
    case grid
    /// Justified rows, as photo sites lay out a gallery: every photo keeps
    /// its shape and every row runs exactly edge to edge.
    case masonry
    /// Equal-width columns of photos at their own heights, each photo going
    /// to whichever column is shortest.
    case columns
    /// One large hero and the rest beside or below it.
    case feature
    /// One row or one column of equal slices — the photobooth strip.
    case strip
    /// White-framed prints, scattered at slight angles and overlapping.
    case polaroid
    /// The magazine two-, three- and four-up: half the page, then the
    /// other half divided. Two photos can be split on a diagonal.
    case split
}

/// How a photo fills its cell.
public enum CollageFit: String, Sendable, Codable, CaseIterable {
    /// Cover the cell, cropping what spills over — around the subject.
    case fill
    /// Show the whole photo inside the cell, the background around it.
    case fit
}

/// The order photos are placed in.
public enum CollageOrder: String, Sendable, Codable, CaseIterable {
    /// The order given.
    case asGiven = "as-given"
    /// Shuffled by the seed, so the same seed gives the same shuffle.
    case shuffle
}

/// Which way a strip runs.
public enum CollageDirection: String, Sendable, Codable, CaseIterable {
    /// Side by side.
    case horizontal
    /// One above another.
    case vertical
}
