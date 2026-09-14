import Foundation

/// One in progress measurement. Holds the two points and the rules for how modifier
/// keys change them, with no knowledge of AppKit or of how anything is drawn.
public struct DrawingSession: Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        case line
        case box
    }

    public var shape: Shape
    public private(set) var anchor: Point
    public private(set) var cursor: Point

    /// Set while the space key is held. Holds the last cursor position seen, so each
    /// further move can be applied as a delta to both ends at once.
    private var moveReference: Point?

    public init(shape: Shape, anchor: Point) {
        self.shape = shape
        self.anchor = anchor
        self.cursor = anchor
    }

    public var isMoving: Bool { moveReference != nil }

    public mutating func move(to point: Point) {
        guard let reference = moveReference else {
            cursor = point
            return
        }
        let dx = point.x - reference.x
        let dy = point.y - reference.y
        anchor = Point(x: anchor.x + dx, y: anchor.y + dy)
        cursor = Point(x: cursor.x + dx, y: cursor.y + dy)
        moveReference = point
    }

    public mutating func beginMoving(from point: Point) {
        moveReference = point
    }

    public mutating func endMoving() {
        moveReference = nil
    }

    public mutating func nudge(dx: Double, dy: Double) {
        cursor = Point(x: cursor.x + dx, y: cursor.y + dy)
    }

    public func line(constrained: Bool) -> LineMeasurement {
        let raw = LineMeasurement(start: anchor, end: cursor)
        return constrained ? raw.constrainedToAxes() : raw
    }

    public func box(constrained: Bool, fromCentre: Bool) -> BoxRect {
        let raw = BoxMeasurement.from(anchor: anchor, cursor: cursor, fromCentre: fromCentre)
        return constrained ? BoxMeasurement.squared(raw, anchor: anchor) : raw
    }
}
