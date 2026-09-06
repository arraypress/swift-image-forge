//
//  SubjectKind.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  What the subject of a picture turned out to be. Reported rather than
//  kept quiet: "cropped around 2 faces" and "cropped around whatever the
//  eye lands on" are different levels of confidence, and a caller batching
//  a thousand photos deserves to know which one it got.
//

import Foundation

/// What kind of thing a crop was centred on.
///
/// The cases are ordered by how much they can be trusted: a face is a fact,
/// attention is a guess.
public enum SubjectKind: String, CaseIterable, Sendable, Codable, Hashable {
    /// One or more faces.
    case face
    /// One or more people, without a face being visible — someone turned
    /// away, or too far off for the face detector.
    case person
    /// A recognised animal: a cat or a dog.
    case animal
    /// A photographed page — the whole document, corner to corner.
    case document
    /// A distinct foreground object, lifted from the background.
    case object
    /// The region the eye is drawn to. A guess, and the last resort before
    /// giving up.
    case attention

    /// How much to trust it, from 1 (a face) to 5 (a guess). Lower is better.
    public var rank: Int {
        switch self {
        case .face: return 1
        case .person: return 2
        case .animal: return 3
        case .document: return 4
        case .object: return 5
        case .attention: return 6
        }
    }

    /// Whether this kind was found by a detector that names a thing, rather
    /// than by a model estimating where the interest is.
    ///
    /// A face, a person, an animal and a page are things with names.
    /// Objectness and attention are both saliency models — one estimating
    /// where objects are, the other where the eye goes — and neither can
    /// say what it found, so neither counts.
    public var isDefinite: Bool {
        switch self {
        case .face, .person, .animal, .document: return true
        case .object, .attention: return false
        }
    }
}
