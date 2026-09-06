//
//  FormatSupport.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  What the running system can actually read and write, asked once and
//  cached. Baking a table in at build time is how a library ends up
//  claiming WebP output on a machine that has never supported it — and how
//  it goes on refusing once a future OS adds it.
//

import Foundation
import ImageIO

/// The codecs ImageIO offers on this machine.
///
/// Measured on macOS 27: 62 formats read, 22 written. The read list runs
/// far wider than the write list — camera RAW from a dozen makers, DICOM,
/// Radiance HDR, the GPU texture containers — and WebP and JPEG XL sit in
/// the gap, readable but not writable.
public enum FormatSupport {

    /// Every uniform type identifier ImageIO can decode.
    public static let readableTypeIdentifiers: Set<String> = {
        Set((CGImageSourceCopyTypeIdentifiers() as? [String]) ?? [])
    }()

    /// Every uniform type identifier ImageIO can encode.
    public static let writableTypeIdentifiers: Set<String> = {
        Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    }()

    /// The named formats this system can write.
    public static var writableFormats: [ImageFormat] {
        ImageFormat.allCases.filter { $0.isWritable }
    }

    /// The named formats this system can read.
    public static var readableFormats: [ImageFormat] {
        ImageFormat.allCases.filter { $0.isReadable }
    }

    /// The closest writable stand-in for a format that cannot be written.
    ///
    /// WebP and JPEG XL both exist to be small and modern on the web; AVIF
    /// is the writable format that answers the same brief, so that is what
    /// they map to. Anything else falls back to PNG, which keeps every pixel.
    public static func alternative(to format: ImageFormat) -> ImageFormat {
        if format.isWritable { return format }
        switch format {
        case .webp, .jpegXL: return .avif
        default: return .png
        }
    }

    /// Checks a format can be written here, or throws an error that names
    /// the alternative.
    public static func requireWritable(_ format: ImageFormat) throws {
        guard !format.isWritable else { return }
        throw ImageForgeError.formatNotWritable(format, alternative: alternative(to: format))
    }
}
