//
//  AnimationSpec.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// How an animation is written.
public struct AnimationSpec: Sendable, Codable, Equatable, Hashable {
    /// How many times to play. 0 loops forever, which is what a GIF on the
    /// web almost always wants.
    public var loopCount: Int
    /// Override every frame's delay with this one, in seconds. Nil keeps
    /// the durations the frames arrived with.
    public var frameDuration: Double?
    /// Keep only every nth frame. 2 halves the frame count — the cheapest
    /// way to shrink a GIF after the dimensions are already as small as
    /// they can go.
    public var frameStride: Int
    /// Play the frames back to front.
    public var reversed: Bool
    /// Append the reverse of the sequence, so the loop runs forward then
    /// back with no jump. Doubles the frame count, less the shared ends.
    public var pingPong: Bool

    /// - Parameters:
    ///   - loopCount: Times to play; 0 for forever.
    ///   - frameDuration: A single delay for every frame, or nil to keep each frame's own.
    ///   - frameStride: Keep every nth frame.
    ///   - reversed: Play back to front.
    ///   - pingPong: Play forward, then back.
    public init(loopCount: Int = 0, frameDuration: Double? = nil,
                frameStride: Int = 1, reversed: Bool = false,
                pingPong: Bool = false) {
        self.loopCount = max(0, loopCount)
        self.frameDuration = frameDuration.map { max(0.01, $0) }
        self.frameStride = max(1, frameStride)
        self.reversed = reversed
        self.pingPong = pingPong
    }

    /// Loop forever at the frames' own speed.
    public static let `default` = AnimationSpec()

    /// Play the animation backwards.
    public static let reverse = AnimationSpec(reversed: true)
}
