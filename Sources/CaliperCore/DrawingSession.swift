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

    /// Where the shape is drawn relative to where its points actually are, used while
    /// it is clipped to a nearby edge. Held separately so that clipping never becomes
    /// permanent: move away and the shape follows the cursor again, because the points
    /// underneath were never touched.
    public private(set) var snapOffset: Point = Point(x: 0, y: 0)

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

        // Fold the clipping into the real points, so letting go of space keeps the
        // shape where the user last saw it rather than snapping it back.
        anchor = Point(x: anchor.x + snapOffset.x, y: anchor.y + snapOffset.y)
        cursor = Point(x: cursor.x + snapOffset.x, y: cursor.y + snapOffset.y)
        snapOffset = Point(x: 0, y: 0)
    }

    public mutating func setSnapOffset(dx: Double, dy: Double) {
        snapOffset = Point(x: dx, y: dy)
    }

    private func clipped(_ point: Point) -> Point {
        Point(x: point.x + snapOffset.x, y: point.y + snapOffset.y)
    }

    public mutating func nudge(dx: Double, dy: Double) {
        cursor = Point(x: cursor.x + dx, y: cursor.y + dy)
    }

    public func line(constrained: Bool) -> LineMeasurement {
        let raw = LineMeasurement(start: clipped(anchor), end: clipped(cursor))
        return constrained ? raw.constrainedToAxes() : raw
    }

    public func box(constrained: Bool, fromCentre: Bool) -> BoxRect {
        let start = clipped(anchor)
        let end = clipped(cursor)
        let raw = BoxMeasurement.from(anchor: start, cursor: end, fromCentre: fromCentre)
        guard constrained else { return raw }
        return BoxMeasurement.squared(raw, anchor: start, fromCentre: fromCentre)
    }
}
