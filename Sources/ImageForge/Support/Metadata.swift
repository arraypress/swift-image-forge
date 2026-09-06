//
//  Metadata.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Deciding what of a file's EXIF, IPTC and XMP reaches the output. The
//  policy is applied to the properties dictionary before it is handed to
//  the destination, so nothing has to be removed after the fact.
//

import Foundation
import ImageIO

/// Filters an image's properties according to a policy.
public enum Metadata {

    /// The property dictionaries that describe the camera and the capture,
    /// as opposed to the author, the rights or the editing history.
    static let captureDictionaries: Set<String> = [
        kCGImagePropertyExifDictionary as String,
        kCGImagePropertyTIFFDictionary as String,
        kCGImagePropertyExifAuxDictionary as String,
    ]

    /// The keys that carry a location, wherever they appear.
    static let locationDictionaries: Set<String> = [
        kCGImagePropertyGPSDictionary as String,
    ]

    /// The maker-note dictionaries, which hold whatever a manufacturer felt
    /// like recording and are dropped by every policy but `.keep`.
    static let makerDictionaries: Set<String> = [
        kCGImagePropertyMakerAppleDictionary as String,
        kCGImagePropertyMakerCanonDictionary as String,
        kCGImagePropertyMakerNikonDictionary as String,
        kCGImagePropertyMakerMinoltaDictionary as String,
        kCGImagePropertyMakerFujiDictionary as String,
        kCGImagePropertyMakerOlympusDictionary as String,
        kCGImagePropertyMakerPentaxDictionary as String,
    ]

    /// Applies a policy to a source's properties.
    ///
    /// - Parameters:
    ///   - properties: The dictionary read from the source.
    ///   - policy: What is allowed through.
    ///   - orientation: The EXIF orientation to write. The default of 1 is
    ///     right for the render path, where the pixels have already been
    ///     turned upright; the passthrough path must pass the source's own
    ///     orientation, because there the pixels are still as stored.
    /// - Returns: The dictionary to hand to the destination.
    public static func filtered(_ properties: [String: Any],
                                policy: MetadataPolicy,
                                orientation: Int = 1) -> [String: Any] {
        var result: [String: Any]

        switch policy {
        case .keep:
            result = properties
        case .stripLocation:
            result = properties
            for key in locationDictionaries { result.removeValue(forKey: key) }
        case .captureOnly:
            result = properties.filter { captureDictionaries.contains($0.key) }
            for key in makerDictionaries { result.removeValue(forKey: key) }
            if var exif = result[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                for key in makerDictionaries { exif.removeValue(forKey: key) }
                result[kCGImagePropertyExifDictionary as String] = exif
            }
        case .strip:
            result = [:]
        }

        result[kCGImagePropertyOrientation as String] = orientation
        return result
    }

    /// Whether a properties dictionary records where the photo was taken.
    ///
    /// - Parameter properties: The dictionary read from the source.
    /// - Returns: True when a GPS dictionary with coordinates is present.
    public static func hasLocation(_ properties: [String: Any]) -> Bool {
        guard let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] else {
            return false
        }
        return gps[kCGImagePropertyGPSLatitude as String] != nil
            || gps[kCGImagePropertyGPSLongitude as String] != nil
    }

    /// The date a photograph records being taken, if it records one.
    ///
    /// EXIF's own `DateTimeOriginal` is preferred over the TIFF date, which
    /// software rewrites on save.
    ///
    /// - Parameter properties: The dictionary read from the source.
    /// - Returns: The capture date, or nil.
    public static func captureDate(_ properties: [String: Any]) -> Date? {
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let text = (exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String)
            ?? (exif?[kCGImagePropertyExifDateTimeDigitized as String] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime as String] as? String)
        guard let text else { return nil }
        return exifDateFormatter.date(from: text)
    }

    /// EXIF writes dates as `2026:09:06 14:22:01`, in no stated time zone.
    static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
