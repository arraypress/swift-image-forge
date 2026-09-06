//
//  SubjectStrategy.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Which detectors to ask, and in what order. `.automatic` is what almost
//  everyone wants; the single-detector cases exist because a batch with a
//  known shape — a folder of portraits, a catalogue of products — is better
//  served by insisting on the right answer than by accepting a fallback.
//

import Foundation

/// How the subject of a picture is found.
public enum SubjectStrategy: String, CaseIterable, Sendable, Codable, Hashable {
    /// Faces, then people, then animals, then foreground objects, then
    /// attention. Stops at the first that finds something.
    ///
    /// Documents are deliberately **not** in this list. Document
    /// segmentation fired at 0.20 on a landscape photograph with no page in
    /// it, and a detector that can be wrong about the whole subject of a
    /// picture does not belong in the path everything takes by default. Ask
    /// for ``documents`` when you know you have one.
    case automatic
    /// Faces only. Falls back to the geometric centre when there are none —
    /// which is what a folder of portraits should do with the one landscape
    /// that got in by mistake.
    case faces
    /// Faces, then people. Everything with a person in it, nothing else.
    case people
    /// Recognised animals only.
    case animals
    /// The page in a photograph of a document, corner to corner.
    case documents
    /// Distinct foreground objects, lifted from the background. The one to
    /// use for products on a plain backdrop.
    case objects
    /// Where the eye is drawn. The cheapest, and the least certain.
    case attention

    /// The detectors this strategy runs, in order, stopping at the first hit.
    public var order: [SubjectKind] {
        switch self {
        case .automatic: return [.face, .person, .animal, .object, .attention]
        case .faces: return [.face]
        case .people: return [.face, .person]
        case .animals: return [.animal]
        case .documents: return [.document]
        case .objects: return [.object]
        case .attention: return [.attention]
        }
    }
}
