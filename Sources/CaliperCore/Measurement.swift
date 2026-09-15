import Foundation

public struct LineMeasurement: Equatable, Sendable {
    public var start: Point
    public var end: Point

    public init(start: Point, end: Point) {
        self.start = start
        self.end = end
    }

    public var dx: Double { end.x - start.x }
    public var dy: Double { end.y - start.y }
    public var distance: Double { (dx * dx + dy * dy).squareRoot() }

    /// Counter clockwise from the positive x axis, in the range 0 up to but not
    /// including 360. Y is negated because y grows downward in this coordinate space,
    /// so a line going up and to the right reads as 45 degrees rather than minus 45.
    public var angleDegrees: Double {
        let radians = atan2(-dy, dx)
        let degrees = radians * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Snaps the line to the nearest multiple of 45 degrees, which is what holding
    /// shift does while drawing. The cursor is projected onto that axis rather than
    /// rotated onto it, so a 100 point drag that runs 8 points off horizontal reads
    /// as exactly 100 rather than keeping its 100.3 hypotenuse. The eight cases are
    /// written out rather than derived with trigonometry, because cos and sin of a
    /// snapped angle leave a horizontal line sitting at 2.4e-14 instead of zero.
    public func constrainedToAxes() -> LineMeasurement {
        let octant = Int((angleDegrees / 45).rounded()) % 8
        let snappedEnd: Point

        switch octant {
        case 0, 4:
            snappedEnd = Point(x: end.x, y: start.y)
        case 2, 6:
            snappedEnd = Point(x: start.x, y: end.y)
        default:
            // The four diagonals. The mean of the two magnitudes is the projection
            // onto the diagonal, and using it for both axes keeps dx and dy equal.
            let reach = (abs(dx) + abs(dy)) / 2
            snappedEnd = Point(x: start.x + (dx < 0 ? -reach : reach),
                               y: start.y + (dy < 0 ? -reach : reach))
        }

        return LineMeasurement(start: start, end: snappedEnd)
    }
}

public enum BoxMeasurement {
    /// Builds a rectangle from a drag. `anchor` is where the mouse went down.
    /// When `fromCentre` is true, which is what holding option does, the anchor
    /// becomes the centre and the box grows outward in both directions.
    public static func from(anchor: Point, cursor: Point, fromCentre: Bool) -> BoxRect {
        if fromCentre {
            let halfWidth = abs(cursor.x - anchor.x)
            let halfHeight = abs(cursor.y - anchor.y)
            return BoxRect(origin: Point(x: anchor.x - halfWidth, y: anchor.y - halfHeight),
                           size: Size(width: halfWidth * 2, height: halfHeight * 2))
        }
        return BoxRect(origin: Point(x: min(anchor.x, cursor.x), y: min(anchor.y, cursor.y)),
                       size: Size(width: abs(cursor.x - anchor.x), height: abs(cursor.y - anchor.y)))
    }

    /// Squares a rectangle to its longer side, which is what shift does on a marquee.
    ///
    /// `anchor` is where the mouse went down. Normally that is the corner the box is
    /// pinned to, but with option held it is the centre instead, and squaring around
    /// a centre is not the same operation as squaring away from a corner. Treating
    /// the two the same leaves the square hanging off a corner while the user is
    /// still holding option, which looks like the box jumping.
    public static func squared(_ box: BoxRect, anchor: Point, fromCentre: Bool) -> BoxRect {
        let side = max(box.size.width, box.size.height)

        if fromCentre {
            return BoxRect(origin: Point(x: anchor.x - side / 2, y: anchor.y - side / 2),
                           size: Size(width: side, height: side))
        }

        let growsRight = box.origin.x >= anchor.x
        let growsDown = box.origin.y >= anchor.y
        let x = growsRight ? anchor.x : anchor.x - side
        let y = growsDown ? anchor.y : anchor.y - side
        return BoxRect(origin: Point(x: x, y: y), size: Size(width: side, height: side))
    }
}
