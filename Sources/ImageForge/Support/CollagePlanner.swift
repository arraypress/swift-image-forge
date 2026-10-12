//
//  CollagePlanner.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//
//  The arithmetic of a collage: where every photo goes, in whole pixels.
//
//  Everything is built on one primitive, `spans`, which divides a length
//  into weighted parts with exact whole-pixel gaps between them. Edges are
//  rounded from the running total rather than part by part, so rounding
//  never accumulates: the parts always meet the far edge exactly and every
//  gap is the gap asked for. A justified row is `spans` over the photos'
//  aspect ratios; a grid is `spans` twice.
//
//  Pure functions over sizes and ratios — no pixels — so every layout is
//  testable against numbers worked out by hand.
//

import CoreGraphics
import Foundation

/// Lays out collages.
enum CollagePlanner {

    /// One photo's place, before any pixels are drawn.
    struct Slot: Equatable {
        /// Which photo, as a position in the placement order.
        var index: Int
        /// The cell, in top-left origin canvas pixels.
        var rect: CGRect
        /// The photo's area inside the cell.
        var photo: CGRect
        /// Clockwise turn, in degrees.
        var rotation: Double = 0
        /// A non-rectangular outline, for a diagonal split.
        var outline: [CGPoint]?

        init(index: Int, rect: CGRect, photo: CGRect? = nil, rotation: Double = 0, outline: [CGPoint]? = nil) {
            self.index = index
            self.rect = rect
            self.photo = photo ?? rect
            self.rotation = rotation
            self.outline = outline
        }
    }

    // MARK: - The primitive

    /// Divides a length into weighted parts with exact gaps between them.
    ///
    /// - Parameters:
    ///   - length: The length to divide, in pixels.
    ///   - weights: Each part's share; only their ratios matter.
    ///   - gap: The space between neighbouring parts, in pixels.
    ///   - origin: Where the length starts.
    /// - Returns: Each part's start and length. The first starts at
    ///   `origin`, the last ends at `origin + length`, and consecutive parts
    ///   are exactly `gap` apart.
    /// - Throws: ``ImageForgeError/collageImpossible(_:)`` when the gaps
    ///   leave less than a pixel per part.
    static func spans(length: Int, weights: [Double], gap: Int, origin: Int = 0) throws -> [(start: Int, length: Int)] {
        guard !weights.isEmpty else { return [] }
        let available = length - gap * (weights.count - 1)
        guard available >= weights.count else {
            throw ImageForgeError.collageImpossible(
                "\(weights.count) photos do not fit in \(length) pixels with \(gap)-pixel gaps")
        }
        let safe = weights.map { $0.isFinite && $0 > 0 ? $0 : 1 }
        let total = safe.reduce(0, +)
        var edges = [0]
        var running = 0.0
        for weight in safe.dropLast() {
            running += weight
            edges.append(Int((Double(available) * running / total).rounded()))
        }
        edges.append(available)
        return (0..<safe.count).map { i in
            (start: origin + edges[i] + i * gap, length: max(1, edges[i + 1] - edges[i]))
        }
    }

    // MARK: - Layouts

    /// Every photo's place in a collage.
    ///
    /// - Parameters:
    ///   - spec: The collage.
    ///   - aspects: Each photo's width over height, in placement order.
    ///   - seed: Seeds the polaroid scatter.
    /// - Returns: One slot per photo, in drawing order.
    /// - Throws: ``ImageForgeError/collageImpossible(_:)``.
    static func plan(_ spec: CollageSpec, aspects: [Double], seed: UInt64) throws -> [Slot] {
        guard !aspects.isEmpty else {
            throw ImageForgeError.collageImpossible("a collage needs at least one photo")
        }
        let content = CGRect(x: spec.margin, y: spec.margin,
                             width: spec.width - 2 * spec.margin, height: spec.height - 2 * spec.margin)
        guard content.width >= 1, content.height >= 1 else {
            throw ImageForgeError.collageImpossible(
                "a \(spec.margin)-pixel margin leaves nothing of a \(spec.width)×\(spec.height) canvas")
        }
        let indices = Array(aspects.indices)
        switch spec.layout {
        case .grid:
            return try grid(indices, in: content, gap: spec.gap, columns: spec.columns, rows: spec.rows)
        case .masonry:
            return try masonry(aspects, in: content, gap: spec.gap)
        case .columns:
            return try columns(aspects, in: content, gap: spec.gap, count: spec.columns)
        case .feature:
            return try feature(indices, hero: spec.hero, in: content, gap: spec.gap)
        case .strip:
            let direction = spec.direction ?? (content.height > content.width ? .vertical : .horizontal)
            return try strip(indices, in: content, gap: spec.gap, direction: direction)
        case .polaroid:
            return polaroid(aspects.count, in: content, seed: seed)
        case .split:
            return try split(indices, in: content, gap: spec.gap, diagonal: spec.diagonal)
        }
    }

    /// Rows and columns of equal cells. A short last row stretches to the
    /// full width rather than leaving a hole.
    static func grid(_ indices: [Int], in area: CGRect, gap: Int,
                     columns: Int? = nil, rows: Int? = nil) throws -> [Slot] {
        let n = indices.count
        let cols: Int
        if let columns {
            cols = max(1, min(columns, n))
        } else if let rows {
            cols = Int((Double(n) / Double(max(1, rows))).rounded(.up))
        } else {
            cols = autoColumns(n, area: area, aspect: 1)
        }
        let rowCount = Int((Double(n) / Double(cols)).rounded(.up))
        let rowSpans = try spans(length: Int(area.height), weights: Array(repeating: 1, count: rowCount),
                                 gap: gap, origin: Int(area.minY))
        var slots: [Slot] = []
        for (r, row) in rowSpans.enumerated() {
            let members = Array(indices[(r * cols)..<min(n, (r + 1) * cols)])
            let colSpans = try spans(length: Int(area.width), weights: Array(repeating: 1, count: members.count),
                                     gap: gap, origin: Int(area.minX))
            for (index, col) in zip(members, colSpans) {
                slots.append(Slot(index: index, rect: CGRect(x: col.start, y: row.start,
                                                             width: col.length, height: row.length)))
            }
        }
        return slots
    }

    /// The column count that makes cells of the given shape closest to
    /// filling an area.
    static func autoColumns(_ n: Int, area: CGRect, aspect: Double) -> Int {
        guard n > 1, area.height > 0 else { return 1 }
        let ideal = (Double(n) * Double(area.width) / (Double(area.height) * aspect)).squareRoot()
        return max(1, min(n, Int(ideal.rounded())))
    }

    /// Justified rows. Photos keep their order and their shape: each row is
    /// divided by aspect ratio so it runs exactly edge to edge, and the row
    /// count is the one whose natural height is closest to the area's. The
    /// last small difference is taken up by scaling every row's height by
    /// the same factor — which a `fill` crop absorbs as a sliver.
    static func masonry(_ aspects: [Double], in area: CGRect, gap: Int) throws -> [Slot] {
        let width = Double(area.width)
        let total = aspects.reduce(0, +)
        // A row of total aspect A at width W is W/A tall, so k rows of
        // roughly equal aspect stand about k²·W/total — solve for k.
        let estimate = max(1, Int((Double(area.height) * total / width).squareRoot().rounded()))
        var best: (rows: [[Int]], error: Double)?
        for k in max(1, estimate - 2)...min(aspects.count, estimate + 2) {
            let rows = partition(aspects, into: k)
            let natural = rows.reduce(0.0) { sum, row in
                let a = row.reduce(0.0) { $0 + aspects[$1] }
                return sum + (width - Double(gap * (row.count - 1))) / a
            } + Double(gap * (k - 1))
            let error = abs(log(natural / Double(area.height)))
            if best == nil || error < best!.error { best = (rows, error) }
        }
        let rows = best!.rows
        let heights = rows.map { row in
            (width - Double(gap * (row.count - 1))) / row.reduce(0.0) { $0 + aspects[$1] }
        }
        let rowSpans = try spans(length: Int(area.height), weights: heights, gap: gap, origin: Int(area.minY))
        var slots: [Slot] = []
        for (row, span) in zip(rows, rowSpans) {
            let cols = try spans(length: Int(area.width), weights: row.map { aspects[$0] },
                                 gap: gap, origin: Int(area.minX))
            for (index, col) in zip(row, cols) {
                slots.append(Slot(index: index, rect: CGRect(x: col.start, y: span.start,
                                                             width: col.length, height: span.length)))
            }
        }
        return slots
    }

    /// Splits a sequence into `k` consecutive runs of near-equal sum — the
    /// linear partition problem, by dynamic programming on squared error.
    static func partition(_ values: [Double], into k: Int) -> [[Int]] {
        let n = values.count
        let k = max(1, min(k, n))
        var prefix = [0.0]
        for v in values { prefix.append(prefix.last! + v) }
        let target = prefix[n] / Double(k)
        // cost[j][i]: best cost of the first i values in j runs.
        var cost = Array(repeating: Array(repeating: Double.infinity, count: n + 1), count: k + 1)
        var cut = Array(repeating: Array(repeating: 0, count: n + 1), count: k + 1)
        cost[0][0] = 0
        for j in 1...k {
            for i in j...n {
                for p in (j - 1)..<i where cost[j - 1][p].isFinite {
                    let run = prefix[i] - prefix[p] - target
                    let c = cost[j - 1][p] + run * run
                    if c < cost[j][i] { cost[j][i] = c; cut[j][i] = p }
                }
            }
        }
        var runs: [[Int]] = []
        var end = n
        for j in stride(from: k, to: 0, by: -1) {
            let start = cut[j][end]
            runs.insert(Array(start..<end), at: 0)
            end = start
        }
        return runs
    }

    /// Equal-width columns, each photo going to the shortest. Every column
    /// is then fitted to the full height — its photos keep their relative
    /// heights — so the bottom edge is straight.
    static func columns(_ aspects: [Double], in area: CGRect, gap: Int, count: Int?) throws -> [Slot] {
        let mean = aspects.reduce(0, +) / Double(aspects.count)
        let k = count.map { max(1, min($0, aspects.count)) } ?? autoColumns(aspects.count, area: area, aspect: mean)
        var members = Array(repeating: [Int](), count: k)
        var heights = Array(repeating: 0.0, count: k)
        for (index, aspect) in aspects.enumerated() {
            let shortest = heights.indices.min { heights[$0] < heights[$1] }!
            members[shortest].append(index)
            heights[shortest] += 1 / aspect
        }
        let colSpans = try spans(length: Int(area.width), weights: Array(repeating: 1, count: k),
                                 gap: gap, origin: Int(area.minX))
        var slots: [Slot] = []
        for (column, span) in zip(members, colSpans) where !column.isEmpty {
            let rows = try spans(length: Int(area.height), weights: column.map { 1 / aspects[$0] },
                                 gap: gap, origin: Int(area.minY))
            for (index, row) in zip(column, rows) {
                slots.append(Slot(index: index, rect: CGRect(x: span.start, y: row.start,
                                                             width: span.length, height: row.length)))
            }
        }
        return slots.sorted { $0.index < $1.index }
    }

    /// One hero across two thirds of the long side, the rest in a grid in
    /// the remaining third.
    static func feature(_ indices: [Int], hero: Int, in area: CGRect, gap: Int) throws -> [Slot] {
        guard indices.indices.contains(hero) else {
            throw ImageForgeError.collageImpossible(
                "the hero is photo \(hero + 1), but there are \(indices.count)")
        }
        guard indices.count > 1 else { return [Slot(index: indices[hero], rect: area)] }
        let rest = indices.enumerated().filter { $0.offset != hero }.map(\.element)
        let wide = area.width >= area.height
        let parts = try spans(length: Int(wide ? area.width : area.height), weights: [2, 1], gap: gap,
                              origin: Int(wide ? area.minX : area.minY))
        let heroRect = wide
            ? CGRect(x: parts[0].start, y: Int(area.minY), width: parts[0].length, height: Int(area.height))
            : CGRect(x: Int(area.minX), y: parts[0].start, width: Int(area.width), height: parts[0].length)
        let restRect = wide
            ? CGRect(x: parts[1].start, y: Int(area.minY), width: parts[1].length, height: Int(area.height))
            : CGRect(x: Int(area.minX), y: parts[1].start, width: Int(area.width), height: parts[1].length)
        return [Slot(index: indices[hero], rect: heroRect)] + (try grid(rest, in: restRect, gap: gap))
    }

    /// Equal slices along one direction.
    static func strip(_ indices: [Int], in area: CGRect, gap: Int, direction: CollageDirection) throws -> [Slot] {
        let along = direction == .horizontal
        let parts = try spans(length: Int(along ? area.width : area.height),
                              weights: Array(repeating: 1, count: indices.count), gap: gap,
                              origin: Int(along ? area.minX : area.minY))
        return zip(indices, parts).map { index, part in
            Slot(index: index, rect: along
                ? CGRect(x: part.start, y: Int(area.minY), width: part.length, height: Int(area.height))
                : CGRect(x: Int(area.minX), y: part.start, width: Int(area.width), height: part.length))
        }
    }

    /// The magazine splits: two halves; a half and two quarters; a half and
    /// three thirds of the other half. Two photos can meet on a diagonal.
    static func split(_ indices: [Int], in area: CGRect, gap: Int, diagonal: Bool) throws -> [Slot] {
        guard (2...4).contains(indices.count) else {
            throw ImageForgeError.collageImpossible(
                "split lays out 2, 3 or 4 photos; \(indices.count) \(indices.count == 1 ? "was" : "were") given — try grid or masonry")
        }
        let wide = area.width >= area.height
        if indices.count == 2, diagonal {
            return diagonalPair(indices, in: area, gap: gap, wide: wide)
        }
        let halves = try spans(length: Int(wide ? area.width : area.height), weights: [1, 1], gap: gap,
                               origin: Int(wide ? area.minX : area.minY))
        let first = wide
            ? CGRect(x: halves[0].start, y: Int(area.minY), width: halves[0].length, height: Int(area.height))
            : CGRect(x: Int(area.minX), y: halves[0].start, width: Int(area.width), height: halves[0].length)
        let second = wide
            ? CGRect(x: halves[1].start, y: Int(area.minY), width: halves[1].length, height: Int(area.height))
            : CGRect(x: Int(area.minX), y: halves[1].start, width: Int(area.width), height: halves[1].length)
        let rest = Array(indices.dropFirst())
        return [Slot(index: indices[0], rect: first)]
            + (try strip(rest, in: second, gap: gap, direction: wide ? .vertical : .horizontal))
    }

    /// Two photos meeting on a slanted line, `gap` pixels apart measured
    /// across the long side.
    static func diagonalPair(_ indices: [Int], in area: CGRect, gap: Int, wide: Bool) -> [Slot] {
        let half = CGFloat(gap) / 2
        if wide {
            let top = area.minX + area.width * 0.6, bottom = area.minX + area.width * 0.4
            let a = [CGPoint(x: area.minX, y: area.minY), CGPoint(x: top - half, y: area.minY),
                     CGPoint(x: bottom - half, y: area.maxY), CGPoint(x: area.minX, y: area.maxY)]
            let b = [CGPoint(x: top + half, y: area.minY), CGPoint(x: area.maxX, y: area.minY),
                     CGPoint(x: area.maxX, y: area.maxY), CGPoint(x: bottom + half, y: area.maxY)]
            return [Slot(index: indices[0], rect: bounds(a), outline: a),
                    Slot(index: indices[1], rect: bounds(b), outline: b)]
        }
        let left = area.minY + area.height * 0.6, right = area.minY + area.height * 0.4
        let a = [CGPoint(x: area.minX, y: area.minY), CGPoint(x: area.maxX, y: area.minY),
                 CGPoint(x: area.maxX, y: right - half), CGPoint(x: area.minX, y: left - half)]
        let b = [CGPoint(x: area.minX, y: left + half), CGPoint(x: area.maxX, y: right + half),
                 CGPoint(x: area.maxX, y: area.maxY), CGPoint(x: area.minX, y: area.maxY)]
        return [Slot(index: indices[0], rect: bounds(a), outline: a),
                Slot(index: indices[1], rect: bounds(b), outline: b)]
    }

    /// The smallest rectangle around some points.
    static func bounds(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// Instant-film prints, scattered. Each print sits on a grid position,
    /// nudged and turned by the seed, and is a little bigger than its cell
    /// so neighbours overlap. The photo is square, with the classic thick
    /// bottom border.
    static func polaroid(_ count: Int, in area: CGRect, seed: UInt64) -> [Slot] {
        var random = SeededRandom(seed: seed)
        let cols = autoColumns(count, area: area, aspect: 0.82)
        let rows = Int((Double(count) / Double(cols)).rounded(.up))
        let cellW = Double(area.width) / Double(cols), cellH = Double(area.height) / Double(rows)
        // A print is the photo plus 6% borders and a 22% bottom: 1.12 wide
        // for 1.28 tall per unit of photo.
        let unit = min(cellW, cellH * 1.12 / 1.28)
        let photoSide = unit, side = unit * 0.06, bottom = unit * 0.22
        let printW = photoSide + 2 * side, printH = photoSide + side + bottom
        var slots: [Slot] = []
        for i in 0..<count {
            let r = i / cols, c = i % cols
            let inRow = r == rows - 1 ? count - r * cols : cols
            // A short last row is centred rather than left-aligned.
            let offset = Double(cols - inRow) * cellW / 2
            let cx = Double(area.minX) + offset + (Double(c) + 0.5) * cellW + random.uniform(-0.08, 0.08) * cellW
            let cy = Double(area.minY) + (Double(r) + 0.5) * cellH + random.uniform(-0.08, 0.08) * cellH
            // Kept inside the area, with room for the corners a turn swings out.
            let padX = printW * 0.56, padY = printH * 0.56
            let x = clamp(cx, Double(area.minX) + padX, Double(area.maxX) - padX, else: Double(area.midX))
            let y = clamp(cy, Double(area.minY) + padY, Double(area.maxY) - padY, else: Double(area.midY))
            let rect = CGRect(x: x - printW / 2, y: y - printH / 2, width: printW, height: printH)
            let photo = CGRect(x: rect.minX + side, y: rect.minY + side, width: photoSide, height: photoSide)
            slots.append(Slot(index: i, rect: rect, photo: photo, rotation: random.uniform(-7, 7)))
        }
        return slots
    }

    /// A value held between two bounds, or a fallback when the bounds have
    /// crossed — a print bigger than the room it has.
    static func clamp(_ value: Double, _ lower: Double, _ upper: Double, else fallback: Double) -> Double {
        lower <= upper ? min(max(value, lower), upper) : fallback
    }

    // MARK: - Cropping

    /// The largest crop of a given shape inside an image, centred on a
    /// focus point and kept inside the frame.
    ///
    /// - Parameters:
    ///   - size: The image, in pixels.
    ///   - aspect: The crop's width over height.
    ///   - focus: The point to centre on, in top-left pixels; nil centres.
    /// - Returns: The crop, in top-left pixels, whole numbers.
    static func crop(_ size: CGSize, aspect: Double, focus: CGPoint?) -> CGRect {
        let imageAspect = Double(size.width / size.height)
        let w = imageAspect > aspect ? Double(size.height) * aspect : Double(size.width)
        let h = imageAspect > aspect ? Double(size.height) : Double(size.width) / aspect
        let centre = focus ?? CGPoint(x: size.width / 2, y: size.height / 2)
        let x = min(max(0, Double(centre.x) - w / 2), Double(size.width) - w)
        let y = min(max(0, Double(centre.y) - h / 2), Double(size.height) - h)
        return CGRect(x: x.rounded(), y: y.rounded(), width: w.rounded(), height: h.rounded())
            .intersection(CGRect(origin: .zero, size: size))
    }

    /// The region a crop centres on, from one detector's findings: all of
    /// them for faces, people and animals, the largest for saliency.
    static func focus(_ regions: [CGRect], kind: SubjectKind) -> CGRect? {
        switch kind {
        case .face, .person, .animal:
            return regions.isEmpty ? nil : regions.dropFirst().reduce(regions[0]) { $0.union($1) }
        default:
            return regions.max { $0.width * $0.height < $1.width * $1.height }
        }
    }

    /// The order photos are placed in.
    static func order(_ count: Int, _ order: CollageOrder, seed: UInt64) -> [Int] {
        guard order == .shuffle else { return Array(0..<count) }
        var random = SeededRandom(seed: seed ^ 0x5DEECE66D)
        var indices = Array(0..<count)
        for i in stride(from: count - 1, to: 0, by: -1) {
            indices.swapAt(i, Int(random.next() % UInt64(i + 1)))
        }
        return indices
    }
}

/// SplitMix64: tiny, fast, and the same sequence on every machine — which
/// `SystemRandomNumberGenerator` is not, and a saved scatter needs.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `lower..<upper`.
    mutating func uniform(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * Double(next() >> 11) / Double(1 << 53)
    }
}
