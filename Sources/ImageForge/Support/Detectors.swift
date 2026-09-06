//
//  Detectors.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Every Vision request this library runs, in one place, each returning a
//  plain model in top-left origin pixels.
//
//  Vision reports in a unit square measured from the LOWER left. Everything
//  else here is pixels from the UPPER left. That conversion happens once, in
//  `boxes(...)` and `quad(...)`, and nowhere else — a detector that
//  half-converts is how a crop ends up mirrored about the horizontal centre
//  and still looks plausible.
//
//  Deliberately NOT here, because the fleet already has a library for each:
//  text recognition (`swift-digital-code-extractor`), barcodes
//  (`swift-qr-kit`), image classification (`swift-image-understanding`),
//  feature prints (`swift-photo-index`) and subject lifting
//  (`swift-object-cutout`). This file holds what informs a *transform*.
//

import CoreGraphics
import Foundation
import Vision

/// The Vision requests behind smart cropping and straightening.
public enum Detectors {

    /// The confidence below which a detection is discarded.
    ///
    /// MEASURED, not chosen. Document segmentation fires on things that are
    /// not documents: on a landscape photograph with no page anywhere in it
    /// it reported 0.20, while synthetic pages photographed at 0°, 4° and 9°
    /// of skew came back at 0.89, 0.92 and 0.98. A floor of 0.5 sits in the
    /// middle of that gap.
    ///
    /// People and faces are floored lower, at 0.3: measured true positives
    /// came in at 0.55, 0.58 and 0.74, and no false positive has been
    /// measured to place the floor against, so it is set to catch obvious
    /// noise rather than to draw a line that has not been tested.
    public enum MinimumConfidence {
        /// The floor for a detected page. Measured; see above.
        public static let document = 0.5
        /// The floor for a face or a person. Conservative; see above.
        public static let body = 0.3
        /// The floor for a recognised animal.
        public static let animal = 0.3
    }

    // MARK: - People and animals

    /// The faces in an image, with pose and, optionally, capture quality.
    ///
    /// - Parameters:
    ///   - image: The image to analyse.
    ///   - includingQuality: Also run the capture-quality request, which is
    ///     a second pass and so is off by default.
    /// - Returns: One entry per face.
    /// - Throws: ``ImageForgeError/analysisFailed(_:)``.
    public static func faces(in image: CGImage, includingQuality: Bool = false,
                             minimumConfidence: Double = MinimumConfidence.body) async throws -> [DetectedFace] {
        let size = image.pixelSize
        do {
            let request = includingQuality
                ? try await DetectFaceCaptureQualityRequest().perform(on: image)
                : try await DetectFaceRectanglesRequest().perform(on: image)
            return request.filter { Double($0.confidence) >= minimumConfidence }.map { face in
                DetectedFace(rect: face.boundingBox.toImageCoordinates(size, origin: .upperLeft),
                             confidence: Double(face.confidence),
                             roll: face.roll.converted(to: .degrees).value,
                             yaw: face.yaw.converted(to: .degrees).value,
                             pitch: face.pitch.converted(to: .degrees).value,
                             quality: face.captureQuality.map { Double($0.score) })
            }
        } catch {
            throw ImageForgeError.analysisFailed(error.localizedDescription)
        }
    }

    /// The people in an image, face visible or not.
    ///
    /// - Parameter image: The image to analyse.
    /// - Returns: One entry per person.
    /// - Throws: ``ImageForgeError/analysisFailed(_:)``.
    public static func people(in image: CGImage,
                              minimumConfidence: Double = MinimumConfidence.body) async throws -> [DetectedPerson] {
        let size = image.pixelSize
        do {
            return try await DetectHumanRectanglesRequest().perform(on: image)
                .filter { Double($0.confidence) >= minimumConfidence }.map {
                DetectedPerson(rect: $0.boundingBox.toImageCoordinates(size, origin: .upperLeft),
                               confidence: Double($0.confidence),
                               isUpperBodyOnly: $0.isUpperBodyOnly)
            }
        } catch {
            throw ImageForgeError.analysisFailed(error.localizedDescription)
        }
    }

    /// The cats and dogs in an image.
    ///
    /// - Parameter image: The image to analyse.
    /// - Returns: One entry per animal, labelled.
    /// - Throws: ``ImageForgeError/analysisFailed(_:)``.
    public static func animals(in image: CGImage,
                               minimumConfidence: Double = MinimumConfidence.animal) async throws -> [DetectedAnimal] {
        let size = image.pixelSize
        do {
            return try await RecognizeAnimalsRequest().perform(on: image)
                .filter { Double($0.confidence) >= minimumConfidence }.map { observation in
                let best = observation.labels.max { $0.confidence < $1.confidence }
                return DetectedAnimal(
                    rect: observation.boundingBox.toImageCoordinates(size, origin: .upperLeft),
                    label: best?.identifier ?? "Animal",
                    confidence: Double(best?.confidence ?? observation.confidence))
            }
        } catch {
            throw ImageForgeError.analysisFailed(error.localizedDescription)
        }
    }

    // MARK: - Regions

    /// The salient regions of an image.
    ///
    /// - Parameters:
    ///   - image: The image to analyse.
    ///   - objectness: Ask for distinct objects rather than for where the
    ///     eye is drawn. Objectness finds *things*; attention finds
    ///     *interest*, and on a picture of nothing in particular attention
    ///     still answers while objectness returns nothing.
    /// - Returns: The regions found, possibly empty.
    /// - Throws: ``ImageForgeError/analysisFailed(_:)``.
    public static func salientRegions(in image: CGImage,
                                      objectness: Bool) async throws -> [CGRect] {
        let size = image.pixelSize
        do {
            let observation = objectness
                ? try await GenerateObjectnessBasedSaliencyImageRequest().perform(on: image)
                : try await GenerateAttentionBasedSaliencyImageRequest().perform(on: image)
            return observation.salientObjects.map {
                $0.boundingBox.toImageCoordinates(size, origin: .upperLeft)
            }
        } catch {
            throw ImageForgeError.analysisFailed(error.localizedDescription)
        }
    }

    /// The page in a photograph of a document, as four corners.
    ///
    /// - Parameters:
    ///   - image: The image to analyse.
    ///   - minimumConfidence: The floor below which a detection is treated
    ///     as the false positive it almost certainly is. See
    ///     ``MinimumConfidence/document``.
    /// - Returns: The page's outline, or nil when there is no document.
    /// - Throws: ``ImageForgeError/analysisFailed(_:)``.
    public static func document(in image: CGImage,
                                minimumConfidence: Double = MinimumConfidence.document) async throws -> Quadrilateral? {
        do {
            guard let observation = try await DetectDocumentSegmentationRequest().perform(on: image),
                  Double(observation.confidence) >= minimumConfidence else {
                return nil
            }
            return quad(observation, in: image.pixelSize, confidence: Double(observation.confidence))
        } catch {
            throw ImageForgeError.analysisFailed(error.localizedDescription)
        }
    }

    /// The four-sided shapes in an image — screens, signs, picture frames.
    ///
    /// - Parameter image: The image to analyse.
    /// - Returns: One entry per shape, most confident first.
    /// - Throws: ``ImageForgeError/analysisFailed(_:)``.
    public static func rectangles(in image: CGImage) async throws -> [Quadrilateral] {
        let size = image.pixelSize
        do {
            return try await DetectRectanglesRequest().perform(on: image)
                .map { quad($0, in: size, confidence: Double($0.confidence)) }
                .sorted { $0.confidence > $1.confidence }
        } catch {
            throw ImageForgeError.analysisFailed(error.localizedDescription)
        }
    }

    // MARK: - The whole frame

    /// How far the horizon is from level, in degrees.
    ///
    /// Positive means the picture leans one way, negative the other; feeding
    /// the negation of this to a rotation levels it.
    ///
    /// - Parameter image: The image to analyse.
    /// - Returns: The angle in degrees, or nil when no horizon was found —
    ///   an indoor photograph usually has none.
    /// - Throws: ``ImageForgeError/analysisFailed(_:)``.
    public static func horizonAngle(in image: CGImage) async throws -> Double? {
        do {
            guard let observation = try await DetectHorizonRequest().perform(on: image) else {
                return nil
            }
            return observation.angle.converted(to: .degrees).value
        } catch {
            throw ImageForgeError.analysisFailed(error.localizedDescription)
        }
    }

    /// How good a photograph this is, from -1 to 1, and whether it is a
    /// utility shot — a screenshot, a receipt, a document — rather than a
    /// picture somebody took for its own sake.
    ///
    /// - Parameter image: The image to analyse.
    /// - Returns: The score and the utility flag.
    /// - Throws: ``ImageForgeError/analysisFailed(_:)``.
    public static func aesthetics(of image: CGImage) async throws -> (score: Double, isUtility: Bool) {
        do {
            let observation = try await CalculateImageAestheticsScoresRequest().perform(on: image)
            return (Double(observation.overallScore), observation.isUtility)
        } catch {
            throw ImageForgeError.analysisFailed(error.localizedDescription)
        }
    }

    /// How sure Vision is that the lens was smudged, from 0 to 1.
    ///
    /// The request arrived in macOS 26, three releases after this library's
    /// floor, so on anything older this returns nil rather than raising the
    /// floor for one optional signal.
    ///
    /// - Parameter image: The image to analyse.
    /// - Returns: The confidence, or nil where the request does not exist.
    /// - Throws: ``ImageForgeError/analysisFailed(_:)``.
    public static func smudgeConfidence(in image: CGImage) async throws -> Double? {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return nil }
        do {
            return Double(try await DetectLensSmudgeRequest().perform(on: image).confidence)
        } catch {
            throw ImageForgeError.analysisFailed(error.localizedDescription)
        }
    }

    // MARK: - Conversion

    /// Turns a Vision quadrilateral into one in top-left origin pixels.
    ///
    /// - Parameters:
    ///   - shape: The observation, in Vision's lower-left unit square.
    ///   - size: The image's size in pixels.
    ///   - confidence: How sure the detector was.
    /// - Returns: The same shape in image coordinates.
    static func quad(_ shape: some QuadrilateralProviding, in size: CGSize,
                     confidence: Double) -> Quadrilateral {
        func point(_ normalized: NormalizedPoint) -> CGPoint {
            CGPoint(x: normalized.x * size.width, y: (1 - normalized.y) * size.height)
        }
        return Quadrilateral(topLeft: point(shape.topLeft), topRight: point(shape.topRight),
                             bottomRight: point(shape.bottomRight),
                             bottomLeft: point(shape.bottomLeft), confidence: confidence)
    }
}

extension Array where Element == CGRect {

    /// The smallest rectangle containing every rectangle in the array, or
    /// nil when it is empty.
    ///
    /// Taking the union rather than the first means a photo of two people
    /// centres between them instead of on one of them.
    var union: CGRect? {
        guard let first else { return nil }
        return dropFirst().reduce(first) { $0.union($1) }
    }
}
