import Foundation

/// Converts between logical points and backing pixels for one display.
///
/// Logical points are what CSS, SwiftUI and AppKit call a pixel. Backing pixels
/// are what the GPU renders and what a screen capture returns. The physical panel
/// resolution is deliberately absent: on a scaled display it is not a whole number
/// multiple of either, and nothing in code ever refers to it.
public struct Scale: Equatable, Sendable {
    public let factor: Double

    public init(factor: Double) {
        self.factor = factor
    }

    public static let retina = Scale(factor: 2.0)
    public static let nonRetina = Scale(factor: 1.0)

    public func points(fromBacking pixels: Double) -> Double {
        pixels / factor
    }

    public func backing(fromPoints points: Double) -> Double {
        points * factor
    }

    /// The precision ceiling of the app. A 2x backing store resolves to half a point,
    /// so every user facing value is snapped to that grid.
    public static func roundedToHalfPoint(_ value: Double) -> Double {
        (value * 2).rounded() / 2
    }
}
