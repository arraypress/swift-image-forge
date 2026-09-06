//
//  ImageFormat.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  The formats this library names. What can be *read* is much wider than
//  what can be *written* — ImageIO on this platform reads 62 types and
//  writes 22 — so every case carries both answers, and `isWritable` asks
//  the running system rather than trusting a table baked in at build time.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An image container format.
///
/// Cases exist for the formats a caller is likely to name. Anything else
/// ImageIO can read still decodes — `ImageInfo.typeIdentifier` carries the
/// raw uniform type identifier for exotic inputs such as camera RAW, DICOM
/// or Radiance HDR, and `ImageInfo.format` is simply `nil` for those.
///
/// ```swift
/// ImageFormat.webp.isWritable   // false on Apple platforms — decode only
/// ImageFormat.avif.isWritable   // true
/// ```
public enum ImageFormat: String, CaseIterable, Sendable, Codable, Hashable {
    /// Lossless, alpha, the safe default for graphics and screenshots.
    case png
    /// Lossy, no alpha, universally readable.
    case jpeg
    /// HEIF in its HEVC flavour — Apple's photo format. Lossy, alpha, gain maps.
    case heic
    /// An animated HEIF sequence.
    case heicSequence
    /// AV1 in HEIF. Lossy, alpha, gain maps, and the only modern web format
    /// this platform can *write*.
    case avif
    /// Lossless, alpha, multi-page, deep bit depths.
    case tiff
    /// 256 colours and animation; still the lingua franca of short loops.
    case gif
    /// Windows bitmap. Uncompressed, no alpha in practice.
    case bmp
    /// Windows icon container — multiple square sizes in one file.
    case ico
    /// Apple icon container — multiple square sizes in one file.
    case icns
    /// JPEG 2000. Lossy or lossless, alpha.
    case jpeg2000
    /// Photoshop document. Written flattened.
    case psd
    /// Truevision Targa.
    case tga
    /// OpenEXR — linear, floating point, the format grading tools expect.
    case openEXR
    /// Portable bitmap.
    case pbm
    /// A PDF page carrying the image.
    case pdf
    /// **Read only on Apple platforms.** Encoding needs libwebp.
    case webp
    /// **Read only on Apple platforms.**
    case jpegXL

    /// The uniform type identifier ImageIO knows this format by.
    public var typeIdentifier: String {
        switch self {
        case .png: return "public.png"
        case .jpeg: return "public.jpeg"
        case .heic: return "public.heic"
        case .heicSequence: return "public.heics"
        case .avif: return "public.avif"
        case .tiff: return "public.tiff"
        case .gif: return "com.compuserve.gif"
        case .bmp: return "com.microsoft.bmp"
        case .ico: return "com.microsoft.ico"
        case .icns: return "com.apple.icns"
        case .jpeg2000: return "public.jpeg-2000"
        case .psd: return "com.adobe.photoshop-image"
        case .tga: return "com.truevision.tga-image"
        case .openEXR: return "com.ilm.openexr-image"
        case .pbm: return "public.pbm"
        case .pdf: return "com.adobe.pdf"
        case .webp: return "org.webmproject.webp"
        case .jpegXL: return "public.jpeg-xl"
        }
    }

    /// The extension to give a file of this format, without the dot.
    public var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .heicSequence: return "heics"
        case .avif: return "avif"
        case .tiff: return "tif"
        case .gif: return "gif"
        case .bmp: return "bmp"
        case .ico: return "ico"
        case .icns: return "icns"
        case .jpeg2000: return "jp2"
        case .psd: return "psd"
        case .tga: return "tga"
        case .openEXR: return "exr"
        case .pbm: return "pbm"
        case .pdf: return "pdf"
        case .webp: return "webp"
        case .jpegXL: return "jxl"
        }
    }

    /// Whether an alpha channel survives a round trip through this format.
    public var supportsAlpha: Bool {
        switch self {
        case .png, .tiff, .gif, .heic, .heicSequence, .avif, .ico, .icns,
             .jpeg2000, .psd, .tga, .openEXR, .webp, .jpegXL:
            return true
        case .jpeg, .bmp, .pbm, .pdf:
            return false
        }
    }

    /// Whether the format holds more than one frame with timing — an animation.
    ///
    /// True for `png`, because an animated PNG *is* a PNG: same container,
    /// same decoders, extra frame chunks. A single-frame encode is still an
    /// ordinary PNG.
    public var supportsAnimation: Bool {
        switch self {
        case .gif, .heicSequence, .png, .webp: return true
        default: return false
        }
    }

    /// Whether a lossy quality between 0 and 1 means anything for this format.
    ///
    /// Passing a quality to a lossless format is not an error; it is ignored.
    public var isLossy: Bool {
        switch self {
        case .jpeg, .heic, .heicSequence, .avif, .jpeg2000: return true
        default: return false
        }
    }

    /// Whether this format can carry an HDR gain map beside its base image.
    ///
    /// A gain map is what makes a modern iPhone photo look bright on an HDR
    /// display and correct on an ordinary one. It survives only a
    /// source-to-destination copy — see ``HDRPolicy``.
    public var supportsGainMap: Bool {
        switch self {
        case .heic, .avif, .jpeg: return true
        default: return false
        }
    }

    /// Whether the format holds several sizes of the same icon in one file.
    public var isIconContainer: Bool {
        self == .ico || self == .icns
    }

    /// Whether ImageIO on the running system can *write* this format.
    ///
    /// Measured, not assumed: the answer comes from
    /// `CGImageDestinationCopyTypeIdentifiers`, so a future OS that gains
    /// WebP encoding starts returning `true` here with no code change.
    public var isWritable: Bool {
        FormatSupport.writableTypeIdentifiers.contains(typeIdentifier)
    }

    /// Whether ImageIO on the running system can *read* this format.
    public var isReadable: Bool {
        FormatSupport.readableTypeIdentifiers.contains(typeIdentifier)
    }

    /// The format a uniform type identifier names, or nil if it is not one
    /// of the named cases. Camera RAW, DICOM and the GPU texture containers
    /// all decode; they simply have no case here.
    public static func named(typeIdentifier: String) -> ImageFormat? {
        allCases.first { $0.typeIdentifier == typeIdentifier }
    }

    /// The format a file extension suggests. Case-insensitive, dot optional.
    ///
    /// `jpeg`, `jpg`, `tif`, `tiff`, `heif` and `jp2` all resolve.
    public static func named(fileExtension: String) -> ImageFormat? {
        let ext = fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch ext {
        case "jpg", "jpeg", "jpe": return .jpeg
        case "tif", "tiff": return .tiff
        case "heif", "heic": return .heic
        case "heics", "heifs": return .heicSequence
        case "jp2", "j2k", "jpf", "jpx": return .jpeg2000
        case "jxl": return .jpegXL
        case "exr": return .openEXR
        default: return allCases.first { $0.fileExtension == ext }
        }
    }
}
