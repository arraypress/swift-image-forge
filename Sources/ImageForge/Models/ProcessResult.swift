//
//  ProcessResult.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  What actually happened — including the parts the caller asked for and
//  did not get. A library that quietly drops an HDR gain map and reports
//  success is the reason this type carries `gainMapPreserved`.
//

import Foundation

/// The outcome of one image job.
public struct ProcessResult: Sendable, Codable, Equatable, Hashable {
    /// Where the image came from. Nil when the input was raw data.
    public let source: URL?
    /// Where it was written. Nil when the output was returned as data.
    public let destination: URL?
    /// What the source was.
    public let before: ImageInfo
    /// What the output is.
    public let after: ImageInfo
    /// The source's size in bytes.
    public let bytesBefore: Int
    /// The output's size in bytes.
    public let bytesAfter: Int
    /// Whether an HDR gain map made it through. False when the source had
    /// none; check ``before`` to tell the two apart.
    public let gainMapPreserved: Bool
    /// Whether the fast path ran — ImageIO copying source to destination
    /// without ever building a `CGImage`. See ``HDRPolicy``.
    public let usedPassthrough: Bool
    /// The operations that were applied, after resolution — a `.smart`
    /// anchor appears here as the rectangle Vision chose.
    public let operations: [ImageOperation]
    /// What the picture turned out to be about, when a `.smart` anchor asked.
    /// Nil when nothing did, and nil when nothing was found.
    public let subject: Subject?
    /// Whether the source was copied byte for byte because the operations
    /// came to nothing. See ``ProcessOptions/copiesWhenUnchanged``.
    public let copiedVerbatim: Bool

    /// - Parameters:
    ///   - source: Where the image came from, if it was a file.
    ///   - destination: Where it was written, if it was written.
    ///   - before: What the source was.
    ///   - after: What the output is.
    ///   - bytesBefore: The source's size in bytes.
    ///   - bytesAfter: The output's size in bytes.
    ///   - gainMapPreserved: Whether a gain map survived.
    ///   - usedPassthrough: Whether the source-to-destination fast path ran.
    ///   - operations: The operations applied, after resolution.
    ///   - subject: What the picture was about, when a `.smart` anchor asked.
    ///   - copiedVerbatim: Whether the source was copied rather than encoded.
    public init(source: URL?, destination: URL?, before: ImageInfo, after: ImageInfo,
                bytesBefore: Int, bytesAfter: Int, gainMapPreserved: Bool,
                usedPassthrough: Bool, operations: [ImageOperation],
                subject: Subject? = nil, copiedVerbatim: Bool = false) {
        self.source = source
        self.destination = destination
        self.before = before
        self.after = after
        self.bytesBefore = bytesBefore
        self.bytesAfter = bytesAfter
        self.gainMapPreserved = gainMapPreserved
        self.usedPassthrough = usedPassthrough
        self.operations = operations
        self.subject = subject
        self.copiedVerbatim = copiedVerbatim
    }

    /// Bytes saved. Negative when the output grew, which a conversion to a
    /// lossless format routinely does.
    public var bytesSaved: Int { bytesBefore - bytesAfter }

    /// The share of the original size that was saved, from 0 to 1.
    /// Negative when the output grew.
    public var savingsRatio: Double {
        bytesBefore == 0 ? 0 : Double(bytesSaved) / Double(bytesBefore)
    }

    /// Whether the source carried a gain map that did *not* survive — the
    /// one outcome worth warning a person about.
    public var lostGainMap: Bool { before.hasGainMap && !gainMapPreserved }
}
