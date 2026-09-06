//
//  FlipAxis.swift
//  ImageForge
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// The axis an image is mirrored across.
public enum FlipAxis: String, CaseIterable, Sendable, Codable, Hashable {
    /// Left becomes right. The mirror selfie.
    case horizontal
    /// Top becomes bottom.
    case vertical
}
