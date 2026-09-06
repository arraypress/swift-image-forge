//
//  TargetSize.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  "Under 500 KB" is a real requirement — an email attachment, an upload
//  limit, a Discord message — and quality is the only dial that answers it.
//  There is no formula from quality to bytes, so the answer is found by
//  encoding: a binary search over quality, keeping the best result that
//  fits, in a fixed number of steps so the cost is predictable.
//

import CoreGraphics
import Foundation

/// Encodes to a byte budget.
public enum TargetSize {

    /// How many encodes the search is allowed. Eight steps resolve quality
    /// to better than one part in 250, which is finer than the encoder's
    /// own granularity.
    public static let searchSteps = 8

    /// The best-quality encode of an image that fits inside a byte budget.
    ///
    /// - Parameters:
    ///   - image: The pixels to write.
    ///   - format: The container to write. A lossless format has no dial to
    ///     turn, so it is encoded once and measured.
    ///   - spec: The rest of the encode settings. Its `quality` is the
    ///     ceiling the search starts from.
    ///   - sourceProperties: The source's properties, for the metadata policy.
    ///   - budget: The most bytes the result may take.
    /// - Returns: The encoded bytes and the quality that produced them.
    /// - Throws: ``ImageForgeError/budgetUnreachable(bytes:smallestAchieved:)``
    ///   when even the lowest quality is too big — at which point the answer
    ///   is to resize, not to compress harder.
    public static func encode(_ image: CGImage, format: ImageFormat, spec: EncodeSpec,
                              sourceProperties: [String: Any]?,
                              budget: Int) throws -> (data: Data, quality: Double) {
        guard format.isLossy else {
            let data = try ImageEncoder.encode(image, format: format, spec: spec,
                                               sourceProperties: sourceProperties)
            guard data.count <= budget else {
                throw ImageForgeError.budgetUnreachable(bytes: budget, smallestAchieved: data.count)
            }
            return (data, spec.quality)
        }

        func attempt(_ quality: Double) throws -> Data {
            var trial = spec
            trial.quality = quality
            trial.maximumBytes = nil
            return try ImageEncoder.encode(image, format: format, spec: trial,
                                           sourceProperties: sourceProperties)
        }

        // The floor first: if the smallest possible encode is too big, no
        // amount of searching will help, and saying so beats eight encodes.
        let smallest = try attempt(0)
        guard smallest.count <= budget else {
            throw ImageForgeError.budgetUnreachable(bytes: budget, smallestAchieved: smallest.count)
        }

        var low = 0.0
        var high = spec.quality
        var best = (data: smallest, quality: 0.0)

        for _ in 0..<searchSteps {
            let mid = (low + high) / 2
            let data = try attempt(mid)
            if data.count <= budget {
                best = (data, mid)
                low = mid
            } else {
                high = mid
            }
        }

        // The ceiling is worth one look: an image that fits at full quality
        // should not be handed back at 99 % of it.
        if let full = try? attempt(spec.quality), full.count <= budget {
            return (full, spec.quality)
        }
        return best
    }
}
