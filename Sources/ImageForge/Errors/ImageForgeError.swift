//
//  ImageForgeError.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Failures a caller can act on. Every message names the thing that was
//  wrong and, where there is one, the way round it — an error that only
//  says "encoding failed" costs somebody an afternoon.
//

import CoreGraphics
import Foundation

/// Why an image operation could not be completed.
public enum ImageForgeError: Error, LocalizedError, Sendable, Equatable {
    /// The file is not there.
    case fileNotFound(URL)
    /// ImageIO could not make sense of the bytes.
    case unreadable(URL)
    /// The file decoded, but holds no image at the index asked for.
    case noImage(URL)
    /// The running system can read this format but cannot write it. Carries
    /// the format asked for and the closest writable alternative.
    case formatNotWritable(ImageFormat, alternative: ImageFormat)
    /// The encoder refused the image — usually a format that cannot hold
    /// what it was given, such as an icon container asked for a non-square.
    case encodingFailed(ImageFormat, reason: String)
    /// A destination file already exists and `ProcessOptions.overwrites` is off.
    case destinationExists(URL)
    /// The file could not be written.
    case writeFailed(URL, reason: String)
    /// A crop rectangle falls outside the image.
    case cropOutOfBounds(requested: CGRect, imageSize: CGSize)
    /// An operation produced an empty image — a crop that keeps nothing, a
    /// resize to zero.
    case emptyResult(String)
    /// A `.smart` anchor reached the synchronous pipeline. Use
    /// ``ImageForge/process(_:to:options:)``, which can await Vision.
    case requiresAsynchronousProcessing
    /// Vision could not analyse the image for a `.smart` crop.
    case analysisFailed(String)
    /// No quality setting could bring the file under the byte budget.
    case budgetUnreachable(bytes: Int, smallestAchieved: Int)
    /// An animation operation was asked of a format that has no frames.
    case notAnimatable(ImageFormat)
    /// An icon container was asked for a size it does not accept. Carries
    /// the sizes it does — they are not the round numbers you would expect.
    case iconSizeUnsupported(ImageFormat, size: Int, supported: [Int])

    /// A lowercase phrase that reads inside a sentence, for a CLI or a log.
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "no file at \(url.path)"
        case .unreadable(let url):
            return "\(url.lastPathComponent) is not an image this system can read"
        case .noImage(let url):
            return "\(url.lastPathComponent) contains no image"
        case .formatNotWritable(let format, let alternative):
            return "\(format.rawValue) can be read but not written on this system — write \(alternative.rawValue) instead"
        case .encodingFailed(let format, let reason):
            return "could not write \(format.rawValue): \(reason)"
        case .destinationExists(let url):
            return "\(url.lastPathComponent) already exists"
        case .writeFailed(let url, let reason):
            return "could not write \(url.lastPathComponent): \(reason)"
        case .cropOutOfBounds(let rect, let size):
            return "crop \(Int(rect.width))×\(Int(rect.height)) at \(Int(rect.minX)),\(Int(rect.minY)) falls outside a \(Int(size.width))×\(Int(size.height)) image"
        case .emptyResult(let step):
            return "\(step) left nothing to encode"
        case .requiresAsynchronousProcessing:
            return "a smart crop needs the asynchronous process method"
        case .analysisFailed(let why):
            return "could not find the subject: \(why)"
        case .budgetUnreachable(let bytes, let smallest):
            return "cannot reach \(bytes) bytes; the smallest encode was \(smallest) — resize first"
        case .notAnimatable(let format):
            return "\(format.rawValue) does not hold animation"
        case .iconSizeUnsupported(let format, let size, let supported):
            let list = supported.map(String.init).joined(separator: ", ")
            return "\(format.rawValue) does not accept \(size)px icons; it takes \(list)"
        }
    }
}
