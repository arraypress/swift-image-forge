//
//  CollageSpec.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  Everything that decides how a collage looks, as one Codable value — so a
//  layout made once can be saved, diffed and laid over another set of
//  photos without anybody remembering the flags.
//

import Foundation

/// What sits behind the photos.
///
/// Written as `{"color": "#2B2B2B"}` or `{"image": "/path/to/bg.jpg"}` —
/// readable in a saved recipe, unlike the `{"color": {"_0": …}}` Swift would
/// otherwise synthesise.
public enum CollageBackground: Sendable, Codable, Equatable {
    /// A flat colour.
    case color(ForgeColor)
    /// A picture, covering the canvas.
    case image(URL)

    private enum Key: String, CodingKey { case color, image }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        if let path = try container.decodeIfPresent(String.self, forKey: .image) {
            self = .image(URL(fileURLWithPath: path))
        } else {
            let hex = try container.decode(String.self, forKey: .color)
            guard let color = ForgeColor(hex: hex) else {
                throw DecodingError.dataCorruptedError(forKey: .color, in: container,
                                                       debugDescription: "\(hex) is not a #RRGGBB(AA) colour")
            }
            self = .color(color)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .color(let color): try container.encode(color.hex, forKey: .color)
        case .image(let url): try container.encode(url.path, forKey: .image)
        }
    }
}

/// How to lay photos out as one picture.
public struct CollageSpec: Sendable, Codable, Equatable {
    /// The arrangement.
    public var layout: CollageLayout
    /// The canvas width, in pixels.
    public var width: Int
    /// The canvas height, in pixels.
    public var height: Int
    /// The space between photos, in pixels. Polaroids overlap instead.
    public var gap: Int
    /// The space around the edge, in pixels.
    public var margin: Int
    /// The corner radius of each photo, in pixels.
    public var radius: Int
    /// What sits behind the photos.
    public var background: CollageBackground
    /// How each photo fills its cell.
    public var fit: CollageFit
    /// The order photos are placed in.
    public var order: CollageOrder
    /// Seeds the shuffle and the polaroid scatter. Nil picks one, and the
    /// result says which, so a scatter that worked can be kept.
    public var seed: UInt64?
    /// Which photo is the hero of a `feature` layout, counting from 0.
    public var hero: Int
    /// The column count for `grid` and `columns`; nil works it out.
    public var columns: Int?
    /// The row count for `grid`; nil works it out.
    public var rows: Int?
    /// Which way a `strip` runs; nil follows the canvas — a tall canvas
    /// stacks, a wide one runs across.
    public var direction: CollageDirection?
    /// Split two photos on a diagonal rather than straight down the middle.
    public var diagonal: Bool
    /// Write each photo's file name on it.
    public var captions: Bool

    /// - Parameters:
    ///   - layout: The arrangement.
    ///   - width: The canvas width, in pixels.
    ///   - height: The canvas height, in pixels.
    ///   - gap: The space between photos, in pixels.
    ///   - margin: The space around the edge, in pixels.
    ///   - radius: The corner radius of each photo, in pixels.
    ///   - background: What sits behind the photos.
    ///   - fit: How each photo fills its cell.
    ///   - order: The order photos are placed in.
    ///   - seed: Seeds the shuffle and the scatter; nil picks one.
    ///   - hero: The hero of a `feature` layout, counting from 0.
    ///   - columns: The column count for `grid` and `columns`.
    ///   - rows: The row count for `grid`.
    ///   - direction: Which way a `strip` runs.
    ///   - diagonal: Split two photos on a diagonal.
    ///   - captions: Write each photo's file name on it.
    public init(layout: CollageLayout = .grid, width: Int = 2400, height: Int = 2400,
                gap: Int = 16, margin: Int = 16, radius: Int = 0,
                background: CollageBackground = .color(.white), fit: CollageFit = .fill,
                order: CollageOrder = .asGiven, seed: UInt64? = nil, hero: Int = 0,
                columns: Int? = nil, rows: Int? = nil, direction: CollageDirection? = nil,
                diagonal: Bool = false, captions: Bool = false) {
        self.layout = layout
        self.width = width
        self.height = height
        self.gap = gap
        self.margin = margin
        self.radius = radius
        self.background = background
        self.fit = fit
        self.order = order
        self.seed = seed
        self.hero = hero
        self.columns = columns
        self.rows = rows
        self.direction = direction
        self.diagonal = diagonal
        self.captions = captions
    }
}
