//
//  IconSizes.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Which square sizes an icon container will actually accept. MEASURED,
//  by writing one image at every plausible size and asking whether the
//  encoder finalised, because the obvious guesses are wrong in both
//  directions:
//
//    · `.icns` refuses **64** — the size sitting right in the middle of the
//      run 16/32/64/128 that every icon guide lists — and refuses **1024**,
//      which is the size macOS asks for as 512@2x.
//    · `.ico` refuses everything above **256**, and accepts the odd **72**.
//    · Neither takes 20, 40, 96 or 180, so the 180 an `apple-touch-icon`
//      wants cannot live in a `.ico` at all.
//
//  An unsupported size does not error at the point it is added: the
//  encoder accepts the image and then fails at finalise, having lost the
//  whole file. So the sizes are checked before a single one is written.
//

import Foundation

/// The square sizes each icon container accepts.
public enum IconSizes {

    /// Sizes an `.icns` accepts, ascending.
    public static let icns: [Int] = [16, 24, 32, 48, 128, 256, 512]

    /// Sizes an `.ico` accepts, ascending.
    public static let ico: [Int] = [16, 24, 32, 48, 64, 72, 128, 256]

    /// The sizes a format accepts, or nil when it is not an icon container.
    ///
    /// - Parameter format: The container to ask about.
    /// - Returns: The accepted square edge lengths, ascending.
    public static func supported(for format: ImageFormat) -> [Int]? {
        switch format {
        case .icns: return icns
        case .ico: return ico
        default: return nil
        }
    }

    /// Whether a container accepts a size.
    ///
    /// - Parameters:
    ///   - side: The square edge length in pixels.
    ///   - format: The container.
    /// - Returns: True when the encoder will take it.
    public static func supports(_ side: Int, in format: ImageFormat) -> Bool {
        supported(for: format)?.contains(side) ?? false
    }

    /// The accepted size closest to the one asked for, for a caller who
    /// would rather round than fail.
    ///
    /// - Parameters:
    ///   - side: The size wanted.
    ///   - format: The container.
    /// - Returns: The nearest accepted size, or nil for a non-container.
    public static func nearest(to side: Int, in format: ImageFormat) -> Int? {
        supported(for: format)?.min { abs($0 - side) < abs($1 - side) }
    }
}
