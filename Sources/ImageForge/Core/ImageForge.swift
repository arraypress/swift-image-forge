//
//  ImageForge.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  The front door. Everything below it is reachable on its own —
//  `Geometry` for the sums, `Renderer` for the pixels, `ImageDecoder` and
//  `ImageEncoder` for the ends — but a caller who just wants a folder of
//  photos made smaller should not have to assemble that.
//

import CoreGraphics
import Foundation
import ImageIO

/// Reads, transforms and writes images.
///
/// ```swift
/// // A photo, bounded and converted, with its gain map intact.
/// let result = try await ImageForge.process(
///     photo, to: output,
///     options: ProcessOptions(operations: [.resize(.longestSide(2048))],
///                             encode: .format(.heic, quality: 0.8))
/// )
/// result.gainMapPreserved   // true — the fast path ran
///
/// // A square thumbnail centred on whatever the eye goes to.
/// try await ImageForge.process(photo, to: thumb, options: ProcessOptions(
///     operations: [.resize(.fill(width: 400, height: 400, anchor: .smart))],
///     encode: .format(.jpeg)
/// ))
/// ```
///
/// Nothing here changes colour or tone. That is
/// [VideoGrade](https://github.com/arraypress/swift-video-grade)'s job, and
/// it composes at the same `CGImage` seam this pipeline works in.
public enum ImageForge {

    // MARK: - Describing

    /// What an image file contains, read from its header.
    ///
    /// - Parameter url: The file to describe.
    /// - Returns: Size, format, orientation, gain map, frame count and more.
    /// - Throws: ``ImageForgeError/fileNotFound(_:)`` or ``ImageForgeError/unreadable(_:)``.
    public static func describe(_ url: URL) throws -> ImageInfo {
        try ImageDecoder.describe(url)
    }

    /// What a block of image data contains.
    ///
    /// - Parameter data: The bytes to describe.
    /// - Returns: Size, format, orientation, gain map, frame count and more.
    /// - Throws: ``ImageForgeError/unreadable(_:)``.
    public static func describe(_ data: Data) throws -> ImageInfo {
        try ImageDecoder.describe(data)
    }

    /// Every frame of an animation, with the time each is held for.
    ///
    /// - Parameters:
    ///   - url: The file to read.
    ///   - maxPixelSize: Decode no frame larger than this on the longest side.
    /// - Returns: The frames, in order.
    /// - Throws: ``ImageForgeError/unreadable(_:)``.
    public static func frames(of url: URL, maxPixelSize: Int? = nil) throws -> [ImageFrame] {
        try ImageDecoder.frames(at: url, maxPixelSize: maxPixelSize)
    }

    /// Everything the detectors can find in an image.
    ///
    /// ```swift
    /// let found = try await ImageForge.detect(photo)
    /// found.summary            // "2 faces, 1 person, horizon +3.4°"
    /// found.subject?.kind      // .face
    /// found.needsStraightening()
    /// ```
    ///
    /// - Parameters:
    ///   - url: The file to analyse.
    ///   - maxPixelSize: Analyse a version no larger than this on the longest
    ///     side. Detection at 2048 px is several times faster than at 44
    ///     megapixels and finds the same things; the rectangles then come
    ///     back in *that* space, which ``Detections/imageSize`` states.
    ///   - includingQuality: Also measure face capture quality and the
    ///     aesthetics score, which are extra passes.
    /// - Returns: Everything found.
    /// - Throws: Any ``ImageForgeError``.
    public static func detect(_ url: URL, maxPixelSize: Int? = nil,
                              includingQuality: Bool = false) async throws -> Detections {
        try await SubjectDetector.detectAll(
            in: try ImageDecoder.image(at: url, maxPixelSize: maxPixelSize),
            includingQuality: includingQuality)
    }

    /// Everything the detectors can find in an image already in memory.
    ///
    /// - Parameters:
    ///   - image: The image to analyse.
    ///   - includingQuality: Also measure face capture quality and the
    ///     aesthetics score.
    /// - Returns: Everything found.
    /// - Throws: ``ImageForgeError/analysisFailed(_:)``.
    public static func detect(_ image: CGImage,
                              includingQuality: Bool = false) async throws -> Detections {
        try await SubjectDetector.detectAll(in: image, includingQuality: includingQuality)
    }

    /// What the picture is about — the one detector call most callers want.
    ///
    /// - Parameters:
    ///   - url: The file to analyse.
    ///   - strategy: Which detectors to ask, and in what order.
    ///   - maxPixelSize: Analyse a version no larger than this.
    /// - Returns: The subject, or nil when nothing was found.
    /// - Throws: Any ``ImageForgeError``.
    public static func subject(of url: URL, strategy: SubjectStrategy = .automatic,
                               maxPixelSize: Int? = nil) async throws -> Subject? {
        try await SubjectDetector.subject(
            of: try ImageDecoder.image(at: url, maxPixelSize: maxPixelSize), strategy: strategy)
    }

    // MARK: - Processing

    /// Runs one image job and writes the result.
    ///
    /// - Parameters:
    ///   - source: The file to read.
    ///   - destination: The file to write. Its extension does not decide the
    ///     format — ``EncodeSpec/format`` does, falling back to the source's.
    ///   - options: What to do and how to write it.
    /// - Returns: What happened, including whether an HDR gain map survived.
    /// - Throws: Any ``ImageForgeError``.
    @discardableResult
    public static func process(_ source: URL, to destination: URL,
                               options: ProcessOptions) async throws -> ProcessResult {
        if FileManager.default.fileExists(atPath: destination.path) && !options.overwrites {
            throw ImageForgeError.destinationExists(destination)
        }
        let outcome = try await encode(source, options: options)
        try ImageEncoder.write(outcome.data, to: destination, overwrites: options.overwrites)

        return ProcessResult(source: source, destination: destination,
                             before: outcome.before,
                             after: try ImageDecoder.describe(destination),
                             bytesBefore: outcome.before.byteCount ?? 0,
                             bytesAfter: outcome.data.count,
                             gainMapPreserved: outcome.gainMapPreserved,
                             usedPassthrough: outcome.usedPassthrough,
                             operations: outcome.operations,
                             subject: outcome.subject,
                             copiedVerbatim: outcome.copiedVerbatim)
    }

    /// Runs one image job and returns the bytes rather than writing them.
    ///
    /// - Parameters:
    ///   - source: The file to read.
    ///   - options: What to do and how to encode it.
    /// - Returns: The encoded image.
    /// - Throws: Any ``ImageForgeError``.
    public static func process(_ source: URL, options: ProcessOptions) async throws -> Data {
        try await encode(source, options: options).data
    }

    /// Runs the same job over many files, writing each into a directory.
    ///
    /// One failure does not stop the others: every input gets a `Result`, in
    /// the order given, so a batch over a folder of mixed files reports the
    /// two that were not images and still converts the other three hundred.
    ///
    /// - Parameters:
    ///   - sources: The files to read.
    ///   - directory: Where to write the results. Created if missing.
    ///   - options: What to do and how to write it.
    /// - Returns: One result per input, in order.
    public static func process(_ sources: [URL], into directory: URL,
                               options: ProcessOptions) async -> [Result<ProcessResult, Error>] {
        var results: [Result<ProcessResult, Error>] = []
        results.reserveCapacity(sources.count)

        for source in sources {
            do {
                let format = try options.encode.format ?? resolvedFormat(of: source)
                let destination = directory
                    .appendingPathComponent(source.deletingPathExtension().lastPathComponent)
                    .appendingPathExtension(format.fileExtension)
                results.append(.success(try await process(source, to: destination, options: options)))
            } catch {
                results.append(.failure(error))
            }
        }
        return results
    }

    // MARK: - Convenience

    /// Converts a file to another format, changing nothing else.
    ///
    /// - Parameters:
    ///   - source: The file to read.
    ///   - format: The format to write.
    ///   - destination: Where to write it. Defaults to the source's path
    ///     with the new extension.
    ///   - quality: Lossy quality from 0 to 1.
    ///   - overwrites: Whether an existing file may be replaced.
    /// - Returns: What happened.
    /// - Throws: Any ``ImageForgeError``.
    @discardableResult
    public static func convert(_ source: URL, to format: ImageFormat,
                               destination: URL? = nil, quality: Double = 0.85,
                               overwrites: Bool = false) async throws -> ProcessResult {
        var options = ProcessOptions.convert(to: format, quality: quality)
        options.overwrites = overwrites
        return try await process(source,
                                 to: destination ?? source.replacingImageExtension(with: format),
                                 options: options)
    }

    /// Writes an icon container holding several sizes of one image.
    ///
    /// - Parameters:
    ///   - source: The image to build from. Cropped square if it is not one.
    ///   - destination: The `.icns` or `.ico` file to write.
    ///   - spec: The sizes and the background behind transparency.
    ///   - overwrites: Whether an existing file may be replaced.
    /// - Returns: The number of bytes written.
    /// - Throws: Any ``ImageForgeError``.
    @discardableResult
    public static func icon(_ source: URL, to destination: URL,
                            spec: IconSpec = .macOS, overwrites: Bool = false) throws -> Int {
        let format = destination.imageFormat ?? .icns
        let image = try ImageDecoder.image(at: source)
        let data = try ImageEncoder.encodeIcon(image, format: format, spec: spec)
        return try ImageEncoder.write(data, to: destination, overwrites: overwrites)
    }

    /// Writes one image at several sizes as separate files — the `@1x`,
    /// `@2x`, `@3x` set an asset catalogue expects.
    ///
    /// - Parameters:
    ///   - source: The image to build from.
    ///   - directory: Where to write the files.
    ///   - spec: The sizes to render.
    ///   - format: The format to write each in.
    ///   - overwrites: Whether existing files may be replaced.
    /// - Returns: The files written, largest first.
    /// - Throws: Any ``ImageForgeError``.
    @discardableResult
    public static func iconSet(_ source: URL, into directory: URL,
                               spec: IconSpec = .scaleFactors(base: 512),
                               format: ImageFormat = .png,
                               overwrites: Bool = false) throws -> [URL] {
        let image = try ImageDecoder.image(at: source)
        let base = source.deletingPathExtension().lastPathComponent

        return try spec.sizes.map { side in
            var rendered = try Renderer.scale(image, to: CGSize(width: side, height: side))
            if spec.background.alpha > 0 {
                rendered = try Renderer.flatten(rendered, onto: spec.background)
            }
            let data = try ImageEncoder.encode(rendered, format: format, spec: EncodeSpec(format: format))
            let url = directory
                .appendingPathComponent("\(base)-\(side)")
                .appendingPathExtension(format.fileExtension)
            try ImageEncoder.write(data, to: url, overwrites: overwrites)
            return url
        }
    }

    /// Builds an animation from separate image files.
    ///
    /// - Parameters:
    ///   - sources: The frames, in order.
    ///   - destination: The file to write.
    ///   - format: The container. Must hold animation — `.gif`, `.png` for
    ///     APNG, or `.heicSequence`.
    ///   - frameDuration: How long each frame is shown, in seconds.
    ///   - animation: Loop count, stride, reversal and ping-pong.
    ///   - encode: Quality and metadata policy.
    ///   - overwrites: Whether an existing file may be replaced.
    /// - Returns: The number of bytes written.
    /// - Throws: ``ImageForgeError/notAnimatable(_:)`` and the rest.
    @discardableResult
    public static func animate(_ sources: [URL], to destination: URL,
                               format: ImageFormat = .gif,
                               frameDuration: Double = 0.1,
                               animation: AnimationSpec = .default,
                               encode: EncodeSpec = EncodeSpec(),
                               overwrites: Bool = false) throws -> Int {
        let frames = try sources.map {
            ImageFrame(image: try ImageDecoder.image(at: $0), duration: frameDuration)
        }
        var spec = animation
        if spec.frameDuration == nil { spec.frameDuration = frameDuration }
        let data = try ImageEncoder.encode(frames: frames, format: format,
                                           spec: encode, animation: spec)
        return try ImageEncoder.write(data, to: destination, overwrites: overwrites)
    }

    // MARK: - The job itself

    /// What one job produced, before it is written anywhere.
    struct Outcome {
        let data: Data
        let before: ImageInfo
        let operations: [ImageOperation]
        let gainMapPreserved: Bool
        let usedPassthrough: Bool
        let subject: Subject?
        let copiedVerbatim: Bool
    }

    /// Reads a source, applies the operations and encodes the result,
    /// choosing between the passthrough and render roads.
    static func encode(_ source: URL, options: ProcessOptions) async throws -> Outcome {
        let before = try ImageDecoder.describe(source)
        let format = try options.encode.format ?? resolvedFormat(of: source)
        try FormatSupport.requireWritable(format)

        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw ImageForgeError.unreadable(source)
        }
        let properties = ImageDecoder.properties(of: imageSource, at: 0)

        // An animated source, asked for as an animation, into a format that
        // holds one: every frame goes through the pipeline.
        if let animation = options.animation, before.isAnimated, format.supportsAnimation {
            let frames = try ImageDecoder.frames(at: source)
            // The subject is found once, on the first frame: an animation
            // whose crop wandered from frame to frame would be unwatchable.
            let analysis = try await analyse(frames[0].image, options: options)
            let resolved = try Pipeline.resolve(options.operations, for: frames[0].image,
                                                subject: analysis.subject,
                                                horizonAngle: analysis.horizonAngle)
            let processed = try frames.map {
                ImageFrame(image: try Pipeline.apply(resolved, to: $0.image), duration: $0.duration)
            }
            let data = try ImageEncoder.encode(frames: processed, format: format,
                                               spec: options.encode, animation: animation)
            return Outcome(data: data, before: before, operations: resolved,
                           gainMapPreserved: false, usedPassthrough: false,
                           subject: analysis.subject, copiedVerbatim: false)
        }

        // The gain map road, when the job is one ImageIO can do on the way past.
        if let maxPixelSize = passthroughPixelSize(options: options, before: before, format: format) {
            let data = try ImageEncoder.passthrough(from: imageSource, format: format,
                                                    spec: options.encode,
                                                    maxPixelSize: maxPixelSize,
                                                    sourceProperties: properties)
            return Outcome(data: data, before: before, operations: options.operations,
                           gainMapPreserved: options.encode.hdr == .preserve,
                           usedPassthrough: true, subject: nil, copiedVerbatim: false)
        }

        // The render road.
        let image = try ImageDecoder.image(at: source, maxPixelSize: decodeHint(for: options))
        let analysis = try await analyse(image, options: options)
        var resolved = try Pipeline.resolve(options.operations, for: image,
                                            subject: analysis.subject,
                                            horizonAngle: analysis.horizonAngle)

        // Nothing to do, and nothing the encode would have changed: hand back
        // the original bytes rather than re-encoding them into a worse copy.
        if options.copiesWhenUnchanged, resolved.isEmpty,
           canCopy(before: before, format: format, encode: options.encode) {
            return Outcome(data: try Data(contentsOf: source), before: before,
                           operations: [], gainMapPreserved: before.hasGainMap,
                           usedPassthrough: false, subject: analysis.subject,
                           copiedVerbatim: true)
        }

        var processed = try Pipeline.apply(resolved, to: image)

        // A format with no alpha needs something behind the image; doing it
        // here rather than in the encoder means it shows up in the report.
        if processed.hasAlphaChannel && !format.supportsAlpha {
            processed = try Renderer.flatten(processed, onto: options.encode.matte)
            resolved.append(.flatten(options.encode.matte))
        }
        processed = try Renderer.convert(processed, to: options.encode.colorSpace)

        let data: Data
        if let budget = options.encode.maximumBytes {
            data = try TargetSize.encode(processed, format: format, spec: options.encode,
                                         sourceProperties: properties, budget: budget).data
        } else {
            data = try ImageEncoder.encode(processed, format: format, spec: options.encode,
                                           sourceProperties: properties)
        }
        return Outcome(data: data, before: before, operations: resolved,
                       gainMapPreserved: false, usedPassthrough: false,
                       subject: analysis.subject, copiedVerbatim: false)
    }

    /// Whether copying the source would be indistinguishable from encoding it.
    ///
    /// Every way the encode could still change the file has to be ruled out,
    /// or "nothing changed" becomes a quiet way of ignoring what was asked:
    /// a different container, a colour conversion, a byte budget, or a
    /// metadata policy with something to remove.
    ///
    /// - Parameters:
    ///   - before: What the source is.
    ///   - format: The format being written.
    ///   - encode: The encode settings.
    /// - Returns: True when the bytes on disk are already the answer.
    static func canCopy(before: ImageInfo, format: ImageFormat, encode: EncodeSpec) -> Bool {
        guard before.format == format,
              encode.colorSpace == .unchanged,
              encode.maximumBytes == nil,
              encode.hdr != .tonemap else { return false }
        switch encode.metadata {
        case .keep: return true
        // The common case: a policy that only drops location, on a file that
        // records none.
        case .stripLocation: return !before.hasLocation
        case .captureOnly, .strip: return false
        }
    }

    /// What the operations need Vision to tell them, and nothing more.
    ///
    /// Each detector is run only if some operation actually asked for it, so
    /// an ordinary resize never loads a model at all.
    ///
    /// - Parameters:
    ///   - image: The image to analyse.
    ///   - options: The job, for its operations and its strategy.
    /// - Returns: The subject and the horizon angle, either possibly nil.
    static func analyse(_ image: CGImage,
                        options: ProcessOptions) async throws -> (subject: Subject?, horizonAngle: Double?) {
        var subject: Subject?
        var horizonAngle: Double?

        if options.operations.contains(where: { operation in
            if case .straighten = operation { return false }
            return operation.needsAnalysis
        }) {
            subject = try await SubjectDetector.subject(of: image, strategy: options.subject)
        }
        if options.operations.contains(where: { if case .straighten = $0 { return true } else { return false } }) {
            horizonAngle = try await Detectors.horizonAngle(in: image)
        }
        return (subject, horizonAngle)
    }

    /// Whether this job can take the passthrough road, and at what size.
    ///
    /// Everything has to line up: a gain map to save, a format that can hold
    /// one, a policy that wants it, and no operation ImageIO cannot perform
    /// on the destination. Returns the longest side to scale to — nil when
    /// the road is closed, and `Optional(nil)` is not a case, so a job with
    /// no resize passes `Int.max` through as "no limit".
    static func passthroughPixelSize(options: ProcessOptions, before: ImageInfo,
                                     format: ImageFormat) -> Int?? {
        guard before.hasGainMap, format.supportsGainMap,
              options.encode.hdr != .discard,
              options.encode.colorSpace == .unchanged,
              options.encode.maximumBytes == nil,
              options.animation == nil,
              options.operations.allSatisfy(\.isPassthroughCapable) else { return nil }

        guard let resize = options.operations.compactMap({ operation -> ResizeSpec? in
            if case .resize(let spec) = operation { return spec }
            return nil
        }).first else {
            return .some(nil)
        }
        let plan = Geometry.plan(resize, source: CGSize(width: before.width, height: before.height))
        return .some(Int(max(plan.scaledSize.width, plan.scaledSize.height)))
    }

    /// The largest the decoder needs to produce for this job.
    ///
    /// When the first thing that happens is a downscale, decoding straight
    /// to that size skips most of the work: a 50-megapixel photo bound to
    /// 2048 px never has 50 megapixels in memory. Anything else decodes in
    /// full, because a crop or a rotation needs the pixels it was promised.
    static func decodeHint(for options: ProcessOptions) -> Int? {
        guard case .resize(let spec)? = options.operations.first,
              !spec.allowsUpscaling, spec.scaleFactor == nil,
              spec.mode != .exact else { return nil }
        return max(spec.width, spec.height)
    }

    /// The format to write when the caller did not name one.
    static func resolvedFormat(of source: URL) throws -> ImageFormat {
        if let format = try? ImageDecoder.describe(source).format, format.isWritable {
            return format
        }
        if let format = source.imageFormat, format.isWritable { return format }
        return .png
    }
}
