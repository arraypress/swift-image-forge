//
//  ImageForge+Collage.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Many photos into one picture. The layout is arithmetic (CollagePlanner),
//  the pixels are Core Graphics (CollageRenderer); this is the part that
//  reads the files, finds what each photo is about so a crop keeps it, and
//  writes the result.
//

import CoreGraphics
import Foundation

public extension ImageForge {

    /// Lays photos out as one picture and writes it.
    ///
    /// ```swift
    /// let result = try await ImageForge.collage(photos, to: out,
    ///                                           spec: CollageSpec(layout: .masonry, width: 1080, height: 1920))
    /// result.cells    // where each photo went, and which part of it shows
    /// ```
    ///
    /// A `fill` crop is centred on what the photo is about — faces first,
    /// then people, animals and Vision's saliency — never blindly on the
    /// middle, which is how a group shot loses its heads.
    ///
    /// - Parameters:
    ///   - sources: The photos, in order.
    ///   - destination: The file to write.
    ///   - spec: The layout and its settings.
    ///   - encode: The format and quality. The format defaults to the
    ///     destination's extension.
    ///   - overwrites: Whether an existing file may be replaced.
    /// - Returns: Where everything went.
    /// - Throws: ``ImageForgeError/collageImpossible(_:)`` and the rest.
    static func collage(_ sources: [URL], to destination: URL, spec: CollageSpec = CollageSpec(),
                        encode: EncodeSpec = EncodeSpec(), overwrites: Bool = false) async throws -> CollageResult {
        let format = encode.format ?? ImageFormat.named(fileExtension: destination.pathExtension) ?? .jpeg
        let made = try await collage(sources, spec: spec)
        let data = try ImageEncoder.encode(made.image, format: format, spec: encode)
        let bytes = try ImageEncoder.write(data, to: destination, overwrites: overwrites)
        return CollageResult(destination: destination, size: made.result.size, cells: made.result.cells,
                             seed: made.result.seed, bytes: bytes, format: format)
    }

    /// Lays photos out as one picture, in memory.
    ///
    /// - Parameters:
    ///   - sources: The photos, in order.
    ///   - spec: The layout and its settings.
    /// - Returns: The picture, and where everything went.
    /// - Throws: ``ImageForgeError/collageImpossible(_:)`` and the rest.
    static func collage(_ sources: [URL], spec: CollageSpec = CollageSpec()) async throws
        -> (image: CGImage, result: CollageResult) {
        guard spec.width > 0, spec.height > 0 else {
            throw ImageForgeError.collageImpossible("a collage needs a size")
        }
        let seed = spec.seed ?? UInt64.random(in: 1...UInt64(UInt32.max))
        let order = CollagePlanner.order(sources.count, spec.order, seed: seed)
        // Decoded no bigger than the canvas: a cell is never larger, and a
        // folder of 50-megapixel photos would otherwise be gigabytes.
        let decodeLimit = max(spec.width, spec.height)
        let images = try order.map { try ImageDecoder.image(at: sources[$0], maxPixelSize: decodeLimit) }
        let slots = try CollagePlanner.plan(spec, aspects: images.map { Double($0.pixelSize.width / $0.pixelSize.height) },
                                            seed: seed)

        var pieces: [CollageRenderer.Piece] = []
        var cells: [CollageCell] = []
        for slot in slots.sorted(by: { $0.index < $1.index }) {
            let image = images[slot.index]
            var crop: CGRect?
            var focus: SubjectKind?
            if spec.fit == .fill {
                let subject = await Self.collageFocus(of: image)
                focus = subject?.kind
                let point = subject.map { CGPoint(x: $0.rect.midX, y: $0.rect.midY) }
                let target = slot.outline.map { CollagePlanner.bounds($0) } ?? slot.photo
                crop = CollagePlanner.crop(image.pixelSize, aspect: Double(target.width / target.height), focus: point)
            }
            let caption = spec.captions ? Self.caption(for: sources[order[slot.index]]) : nil
            pieces.append(CollageRenderer.Piece(image: image, caption: caption, crop: crop))
            cells.append(CollageCell(source: order[slot.index], rect: slot.rect, photoRect: slot.photo,
                                     rotation: slot.rotation, crop: crop, focus: focus, outline: slot.outline))
        }

        let backdrop: CGImage?
        if case .image(let url) = spec.background {
            backdrop = try ImageDecoder.image(at: url, maxPixelSize: decodeLimit)
        } else {
            backdrop = nil
        }
        let image = try CollageRenderer.render(slots, pieces: pieces, spec: spec, backdrop: backdrop)
        let drawn = slots.map { slot in cells.first { $0.source == order[slot.index] }! }
        return (image, CollageResult(destination: nil, size: CGSize(width: spec.width, height: spec.height),
                                     cells: drawn, seed: seed, bytes: 0, format: nil))
    }

    /// What a crop should be centred on: every face, person or animal
    /// together (a group shot keeps all its heads), else the single
    /// largest salient region.
    ///
    /// Not ``SubjectDetector/subject(of:strategy:)``'s union for saliency:
    /// objectness returns stray texture patches beside the real subject, and
    /// their union put the centre of an off-centre owl above its head.
    internal static func collageFocus(of image: CGImage) async -> (rect: CGRect, kind: SubjectKind)? {
        for kind in SubjectStrategy.automatic.order {
            guard let regions = try? await SubjectDetector.regions(of: image, kind: kind),
                  let rect = CollagePlanner.focus(regions, kind: kind) else { continue }
            return (rect, kind)
        }
        return nil
    }

    /// A file name as a caption: `beach_day-2` reads "beach day 2".
    internal static func caption(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}
