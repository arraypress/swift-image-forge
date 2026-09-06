//
//  URL+ImageForge.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension URL {

    /// The image format this file's extension names, if it names one.
    var imageFormat: ImageFormat? {
        ImageFormat.named(fileExtension: pathExtension)
    }

    /// Whether the extension is one ImageIO can read.
    ///
    /// Cheap and wrong at the edges — it reads the name, not the file. Use
    /// ``ImageForge/describe(_:)`` when the answer has to be right.
    var looksLikeAnImage: Bool {
        guard let format = imageFormat else { return false }
        return format.isReadable
    }

    /// The same path with a different extension, for writing a converted copy.
    ///
    /// - Parameter format: The format whose extension to use.
    /// - Returns: The new URL.
    func replacingImageExtension(with format: ImageFormat) -> URL {
        deletingPathExtension().appendingPathExtension(format.fileExtension)
    }

    /// The same name with a suffix before the extension — `photo.jpg`
    /// becomes `photo-small.jpg`.
    ///
    /// - Parameter suffix: The text to add before the extension.
    /// - Returns: The new URL.
    func addingFilenameSuffix(_ suffix: String) -> URL {
        let ext = pathExtension
        let base = deletingPathExtension().lastPathComponent
        return deletingLastPathComponent()
            .appendingPathComponent(base + suffix)
            .appendingPathExtension(ext)
    }
}
