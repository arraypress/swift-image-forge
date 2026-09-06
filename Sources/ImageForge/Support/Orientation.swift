//
//  Orientation.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  A photograph taken sideways is stored sideways, with a tag saying which
//  way up it goes. Software that reads the tag shows it correctly; software
//  that ignores it — half the web — shows it on its side. Baking the tag
//  into the pixels is what makes an image look the same everywhere.
//

import CoreGraphics
import Foundation
import ImageIO

/// EXIF orientation, as operations on pixels.
public enum Orientation {

    /// The turns and mirrors that make an image with this EXIF orientation
    /// upright, in the order they should be applied.
    ///
    /// The eight values are the standard EXIF set: 1 is already upright, the
    /// even ones after 2 are mirrored, and 5 to 8 are the quarter turns.
    ///
    /// - Parameter exif: The EXIF orientation tag, 1 to 8. Anything else is
    ///   treated as 1, since a corrupt tag should not rotate a picture.
    /// - Returns: The operations to apply, possibly empty.
    public static func operations(for exif: Int) -> [ImageOperation] {
        switch exif {
        case 2: return [.flip(.horizontal)]
        case 3: return [.rotate(.oneEighty)]
        case 4: return [.flip(.vertical)]
        case 5: return [.rotate(.ninety), .flip(.horizontal)]
        case 6: return [.rotate(.ninety)]
        case 7: return [.rotate(.twoSeventy), .flip(.horizontal)]
        case 8: return [.rotate(.twoSeventy)]
        default: return []
        }
    }

    /// Whether an EXIF orientation swaps the image's width and height.
    public static func swapsAxes(_ exif: Int) -> Bool {
        (5...8).contains(exif)
    }

    /// The size an image presents at, given how its pixels are stored.
    ///
    /// - Parameters:
    ///   - stored: The size the pixels are stored at.
    ///   - exif: The EXIF orientation tag.
    /// - Returns: The size a person looking at the picture would give.
    public static func displayedSize(stored: CGSize, exif: Int) -> CGSize {
        swapsAxes(exif) ? CGSize(width: stored.height, height: stored.width) : stored
    }

    /// The Core Graphics spelling of an EXIF orientation, for the frameworks
    /// that want it that way — Vision among them.
    public static func propertyOrientation(_ exif: Int) -> CGImagePropertyOrientation {
        CGImagePropertyOrientation(rawValue: UInt32(exif)) ?? .up
    }
}
