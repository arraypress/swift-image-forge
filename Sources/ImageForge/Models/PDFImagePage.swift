//
//  PDFImagePage.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  One page of a PDF made from a picture: the picture, the sheet it sits
//  on, and — when something has read it — the words, so the page can be
//  searched and copied from as if it had been typed.
//

import CoreGraphics
import Foundation

/// A page of a PDF built from an image.
public struct PDFImagePage: @unchecked Sendable {
    /// The picture, filling the page.
    public let image: CGImage
    /// The page's size in PDF points (1/72 in).
    public let size: CGSize
    /// Words to lay invisibly over the picture, where they appear in it.
    public let text: [PDFTextRun]
    /// JPEG quality for the picture, 0 to 1, or nil to store it losslessly
    /// — what a black-and-white page wants, since JPEG smears the one edge
    /// such a page is made of.
    public let jpegQuality: Double?

    /// - Parameters:
    ///   - image: The picture.
    ///   - size: The page size in points.
    ///   - text: Words to lay over it, if any.
    ///   - jpegQuality: JPEG quality, or nil for lossless.
    public init(image: CGImage, size: CGSize, text: [PDFTextRun] = [], jpegQuality: Double? = 0.75) {
        self.image = image
        self.size = size
        self.text = text
        self.jpegQuality = jpegQuality
    }
}

/// A run of text and where it sits on a page.
public struct PDFTextRun: Sendable, Codable, Equatable, Hashable {
    /// The text.
    public let text: String
    /// Where it sits, as a fraction of the page with the origin at the
    /// **bottom left** — the convention Vision and PDF share, so a
    /// recogniser's boxes go straight in.
    public let frame: CGRect

    /// - Parameters:
    ///   - text: The text.
    ///   - frame: Its box, normalised, bottom-left origin.
    public init(text: String, frame: CGRect) {
        self.text = text
        self.frame = frame
    }
}
