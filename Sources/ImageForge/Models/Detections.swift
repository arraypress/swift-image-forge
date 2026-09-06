//
//  Detections.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Everything the detectors can say about one image. Answering "what is in
//  this picture, structurally?" before deciding what to do to it — which
//  crop, whether to straighten, whether it is even worth keeping.
//

import CoreGraphics
import Foundation

/// What was found in an image.
public struct Detections: Sendable, Codable, Equatable, Hashable {
    /// The size of the image everything was measured against, in pixels.
    /// Every rectangle below is in top-left origin pixels of this size.
    public let imageSize: CGSize
    /// The faces.
    public let faces: [DetectedFace]
    /// The people, whether or not their faces were found.
    public let people: [DetectedPerson]
    /// The cats and dogs.
    public let animals: [DetectedAnimal]
    /// Distinct object regions.
    public let objects: [CGRect]
    /// Regions the eye is drawn to.
    public let attention: [CGRect]
    /// A photographed page, if there is one.
    public let document: Quadrilateral?
    /// Four-sided shapes — screens, signs, picture frames.
    public let rectangles: [Quadrilateral]
    /// How far from level the horizon is, in degrees, or nil when there is
    /// no horizon to find.
    public let horizonAngle: Double?
    /// How good a photograph this is, from -1 to 1, when it was measured.
    public let aestheticsScore: Double?
    /// Whether this is a utility image — a screenshot, a receipt, a
    /// document — rather than a picture taken for its own sake.
    public let isUtilityImage: Bool?

    /// - Parameters:
    ///   - imageSize: The size everything was measured against.
    ///   - faces: The faces.
    ///   - people: The people.
    ///   - animals: The animals.
    ///   - objects: Distinct object regions.
    ///   - attention: Regions the eye is drawn to.
    ///   - document: A photographed page, if there is one.
    ///   - rectangles: Four-sided shapes.
    ///   - horizonAngle: Degrees off level, if a horizon was found.
    ///   - aestheticsScore: The aesthetics score, if measured.
    ///   - isUtilityImage: Whether it is a utility image, if measured.
    public init(imageSize: CGSize, faces: [DetectedFace], people: [DetectedPerson],
                animals: [DetectedAnimal], objects: [CGRect], attention: [CGRect],
                document: Quadrilateral?, rectangles: [Quadrilateral],
                horizonAngle: Double?, aestheticsScore: Double?, isUtilityImage: Bool?) {
        self.imageSize = imageSize
        self.faces = faces
        self.people = people
        self.animals = animals
        self.objects = objects
        self.attention = attention
        self.document = document
        self.rectangles = rectangles
        self.horizonAngle = horizonAngle
        self.aestheticsScore = aestheticsScore
        self.isUtilityImage = isUtilityImage
    }

    /// Whether anything at all was found.
    public var isEmpty: Bool {
        faces.isEmpty && people.isEmpty && animals.isEmpty && objects.isEmpty
            && attention.isEmpty && document == nil && rectangles.isEmpty
    }

    /// The most trustworthy subject found, by the same order
    /// ``SubjectStrategy/automatic`` uses.
    public var subject: Subject? {
        let candidates: [(SubjectKind, [CGRect])] = [
            (.face, faces.map(\.rect)),
            (.person, people.map(\.rect)),
            (.animal, animals.map(\.rect)),
            (.document, document.map { [$0.boundingBox] } ?? []),
            (.object, objects),
            (.attention, attention),
        ]
        for (kind, rects) in candidates {
            guard let union = rects.union else { continue }
            return Subject(rect: union, kind: kind, count: rects.count)
        }
        return nil
    }

    /// Whether the picture leans far enough to be worth straightening.
    ///
    /// - Parameter threshold: Degrees below which it is left alone.
    /// - Returns: True when a horizon was found and it is off by more than
    ///   the threshold.
    public func needsStraightening(threshold: Double = 0.5) -> Bool {
        guard let horizonAngle else { return false }
        return abs(horizonAngle) > threshold
    }

    /// A one-line summary for a log or a table.
    public var summary: String {
        var parts: [String] = []
        if !faces.isEmpty { parts.append(faces.count == 1 ? "1 face" : "\(faces.count) faces") }
        if !people.isEmpty { parts.append(people.count == 1 ? "1 person" : "\(people.count) people") }
        for animal in animals { parts.append(animal.label.lowercased()) }
        if document != nil { parts.append("a document") }
        if !rectangles.isEmpty {
            parts.append(rectangles.count == 1 ? "1 rectangle" : "\(rectangles.count) rectangles")
        }
        if let horizonAngle { parts.append(String(format: "horizon %+.1f°", horizonAngle)) }
        if parts.isEmpty && !attention.isEmpty { parts.append("no named subject") }
        return parts.isEmpty ? "nothing found" : parts.joined(separator: ", ")
    }
}
