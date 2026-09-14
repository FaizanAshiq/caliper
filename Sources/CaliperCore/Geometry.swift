import Foundation

/// A position in logical points. Y grows downward, matching CSS and screen intuition.
/// Conversion to AppKit's y-grows-upward screen space happens in CaliperApp only.
public struct Point: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct Size: Equatable, Sendable, Codable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct BoxRect: Equatable, Sendable, Codable {
    public var origin: Point
    public var size: Size

    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
    }
}

public enum Direction: CaseIterable, Sendable {
    case left, right, up, down
}
