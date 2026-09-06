//
//  SubjectDetector.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  What a picture is about, asked of the detectors in order of how much
//  they can be trusted. A face is a fact; attention-based saliency is a
//  model's guess about where the eye lands, and cropping a portrait around
//  a guess is how a thumbnail ends up centred on somebody's shoulder.
//
//  Detectors run one at a time and stop at the first that finds anything,
//  because the certain ones are also the cheap ones — face detection on a
//  landscape costs a few milliseconds and answers "no".
//

import CoreGraphics
import Foundation

/// Finds the subject of a picture.
public enum SubjectDetector {

    /// The subject of an image, or nil when nothing was found.
    ///
    /// - Parameters:
    ///   - image: The image to analyse.
    ///   - strategy: Which detectors to ask, and in what order.
    /// - Returns: The subject and what kind of thing it turned out to be,
    ///   or nil when no detector in the strategy found anything — at which
    ///   point a caller should fall back to the geometric centre.
    /// - Throws: ``ImageForgeError/analysisFailed(_:)`` if Vision refuses the image.
    public static func subject(of image: CGImage,
                               strategy: SubjectStrategy = .automatic) async throws -> Subject? {
        for kind in strategy.order {
            let rects = try await regions(of: image, kind: kind)
            guard let union = rects.union else { continue }
            return Subject(rect: union, kind: kind, count: rects.count)
        }
        return nil
    }

    /// Every region one detector finds, in top-left origin pixels.
    ///
    /// - Parameters:
    ///   - image: The image to analyse.
    ///   - kind: Which detector to run.
    /// - Returns: The regions found, possibly empty.
    /// - Throws: ``ImageForgeError/analysisFailed(_:)``.
    public static func regions(of image: CGImage, kind: SubjectKind) async throws -> [CGRect] {
        switch kind {
        case .face:
            return try await Detectors.faces(in: image).map(\.rect)
        case .person:
            return try await Detectors.people(in: image).map(\.rect)
        case .animal:
            return try await Detectors.animals(in: image).map(\.rect)
        case .document:
            return try await Detectors.document(in: image).map { [$0.boundingBox] } ?? []
        case .object:
            return try await Detectors.salientRegions(in: image, objectness: true)
        case .attention:
            return try await Detectors.salientRegions(in: image, objectness: false)
        }
    }

    /// Everything every detector can say about an image, in one pass over
    /// the list.
    ///
    /// Unlike ``subject(of:strategy:)`` this does not stop early — it is for
    /// a caller who wants to *see* what is in a picture rather than crop it.
    ///
    /// - Parameters:
    ///   - image: The image to analyse.
    ///   - includingQuality: Also measure face capture quality and the
    ///     aesthetics score, which are extra passes.
    /// - Returns: Everything found.
    /// - Throws: ``ImageForgeError/analysisFailed(_:)``.
    public static func detectAll(in image: CGImage,
                                 includingQuality: Bool = false) async throws -> Detections {
        let faces = try await Detectors.faces(in: image, includingQuality: includingQuality)
        let people = try await Detectors.people(in: image)
        let animals = try await Detectors.animals(in: image)
        let objects = try await Detectors.salientRegions(in: image, objectness: true)
        let attention = try await Detectors.salientRegions(in: image, objectness: false)
        let document = try await Detectors.document(in: image)
        let rectangles = try await Detectors.rectangles(in: image)
        let horizon = try await Detectors.horizonAngle(in: image)
        let aesthetics = includingQuality ? try await Detectors.aesthetics(of: image) : nil

        return Detections(imageSize: image.pixelSize, faces: faces, people: people,
                          animals: animals, objects: objects, attention: attention,
                          document: document, rectangles: rectangles,
                          horizonAngle: horizon,
                          aestheticsScore: aesthetics?.score,
                          isUtilityImage: aesthetics?.isUtility)
    }
}
