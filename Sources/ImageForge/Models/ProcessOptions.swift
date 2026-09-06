//
//  ProcessOptions.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  One job: what to do to the pixels, and how to write them out. Codable,
//  so a recipe can live in a JSON file and be applied to a folder.
//

import Foundation

/// A complete image job.
///
/// ```swift
/// let options = ProcessOptions(
///     operations: [.resize(.longestSide(2048)), .crop(.square(anchor: .smart))],
///     encode: .format(.heic, quality: 0.8)
/// )
/// ```
public struct ProcessOptions: Sendable, Codable, Equatable, Hashable {
    /// What to do to the pixels, in order. An empty list is legal and means
    /// "re-encode only", which is how a plain format conversion is written.
    public var operations: [ImageOperation]
    /// How to write the result.
    public var encode: EncodeSpec
    /// How to handle an animated source. Nil treats an animation as a still
    /// and keeps only its first frame.
    public var animation: AnimationSpec?
    /// How the subject is found when an operation asks for a `.smart`
    /// anchor. Ignored when none does.
    public var subject: SubjectStrategy
    /// Copy the source verbatim when the operations come to nothing.
    ///
    /// Some operations resolve to nothing at all: `.straighten` on a picture
    /// with no horizon, `.crop(.subject)` on one with no subject. Without
    /// this, such a job still decodes and re-encodes — which for a JPEG
    /// means throwing away quality and often *growing* the file, in exchange
    /// for no change whatsoever.
    ///
    /// Off by default, because a caller asking to re-encode at a new quality
    /// means it. Turn it on for verbs where "nothing to do" is a real answer.
    /// The copy is only taken when it would be indistinguishable from the
    /// encode: same format, no colour conversion, no byte budget, and no
    /// metadata the policy would have removed.
    public var copiesWhenUnchanged: Bool
    /// Whether an existing file at the destination may be replaced.
    public var overwrites: Bool

    /// - Parameters:
    ///   - operations: What to do to the pixels, in order.
    ///   - encode: How to write the result.
    ///   - animation: How to handle an animated source, or nil to keep only
    ///     the first frame.
    ///   - subject: How to find the subject for a `.smart` anchor.
    ///   - copiesWhenUnchanged: Copy rather than re-encode when the
    ///     operations come to nothing.
    ///   - overwrites: Whether an existing destination file may be replaced.
    public init(operations: [ImageOperation] = [],
                encode: EncodeSpec = EncodeSpec(),
                animation: AnimationSpec? = nil,
                subject: SubjectStrategy = .automatic,
                copiesWhenUnchanged: Bool = false,
                overwrites: Bool = false) {
        self.operations = operations
        self.encode = encode
        self.animation = animation
        self.subject = subject
        self.copiesWhenUnchanged = copiesWhenUnchanged
        self.overwrites = overwrites
    }

    /// Convert to a format and change nothing else.
    public static func convert(to format: ImageFormat, quality: Double = 0.85) -> ProcessOptions {
        ProcessOptions(encode: .format(format, quality: quality))
    }

    /// Bound the image's longest side, keeping its format.
    public static func resize(longestSide pixels: Int) -> ProcessOptions {
        ProcessOptions(operations: [.resize(.longestSide(pixels))])
    }

    /// Whether any operation needs Vision, and so needs the asynchronous
    /// entry point.
    public var needsAnalysis: Bool {
        operations.contains { $0.needsAnalysis }
    }
}
