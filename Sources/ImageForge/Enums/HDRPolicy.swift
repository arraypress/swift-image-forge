//
//  HDRPolicy.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Modern phone photos are an SDR base image plus a *gain map* — a second
//  channel telling a bright display how much further to push each pixel.
//  The trap: a gain map is not part of a CGImage. Decode to a CGImage, do
//  anything at all, encode again, and the HDR is silently gone; the picture
//  still looks fine, just flat on the display it was shot for.
//

import Foundation

/// What happens to an image's HDR gain map.
///
/// Preserving one constrains the pipeline: the gain map only survives a
/// direct source-to-destination copy, so `.preserve` is honoured for
/// operations ImageIO can perform on the destination — a format change, a
/// re-encode at a new quality, a downscale — and is reported as *not*
/// honoured for anything needing a render, such as a crop or a rotation.
/// ``ProcessResult/gainMapPreserved`` says which happened, so a caller is
/// never left guessing.
public enum HDRPolicy: String, CaseIterable, Sendable, Codable, Hashable {
    /// Keep the gain map where the operations allow it. The default.
    case preserve
    /// Bake the HDR into the base image and write an ordinary SDR file.
    /// The result looks the same everywhere, and is smaller.
    case tonemap
    /// Drop the gain map without tone mapping. The base image as it stands.
    case discard

    /// Whether the destination should be asked to carry the gain map through.
    public var wantsGainMap: Bool { self == .preserve }
}
