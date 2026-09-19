import Foundation

/// Finds element boundaries by walking outward from a point through a captured frame,
/// looking for a change in brightness that holds for several pixels. It reads what is
/// drawn rather than any accessibility tree, so it works equally on a native button,
/// a canvas, a video frame or a screenshot of a design.
public struct EdgeDetector: Sendable {
    /// Brightness difference, 0 to 1, that counts as a boundary.
    public var threshold: Double
    /// How many consecutive pixels must stay changed. Rejects noise and soft shadows.
    public var runLength: Int

    public init(threshold: Double, runLength: Int) {
        self.threshold = threshold
        self.runLength = runLength
    }

    /// A boundary counts once it has held for one logical point, which is however
    /// many backing pixels that display puts in a point.
    ///
    /// A fixed run of three pixels was a point and a half on a retina display, and a
    /// hairline is a point. The rule between two table rows could never satisfy it, at
    /// any threshold, so a row had no top and no bottom and the reading ran the whole
    /// table instead. Counting in points makes the thinnest boundary anything draws
    /// the unit, which is what the run was reaching for and could not say in pixels.
    public init(threshold: Double, scale: Scale) {
        self.init(threshold: threshold, runLength: max(1, Int(scale.factor.rounded())))
    }

    private func step(_ direction: Direction) -> (dx: Int, dy: Int) {
        switch direction {
        case .left:  return (-1, 0)
        case .right: return (1, 0)
        case .up:    return (0, -1)
        case .down:  return (0, 1)
        }
    }

    /// Returns the coordinate of the last pixel still belonging to the region the
    /// origin sits in, along the given axis. Nil when the region runs to the edge of
    /// the buffer without a boundary.
    public func firstEdge(from origin: (x: Int, y: Int),
                          direction: Direction,
                          in buffer: PixelSampling) -> Int? {
        let move = step(direction)
        let reference = buffer.luminance(x: origin.x, y: origin.y)
        var x = origin.x
        var y = origin.y

        while true {
            let nextX = x + move.dx
            let nextY = y + move.dy
            guard nextX >= 0, nextY >= 0, nextX < buffer.width, nextY < buffer.height else {
                return nil
            }

            if abs(buffer.luminance(x: nextX, y: nextY) - reference) >= threshold,
               holds(from: (nextX, nextY), direction: direction, reference: reference, in: buffer) {
                return direction == .left || direction == .right ? x : y
            }

            x = nextX
            y = nextY
        }
    }

    /// Confirms a candidate boundary by checking the change persists for runLength
    /// pixels. A single stray pixel or an antialiased fringe fails this.
    private func holds(from start: (x: Int, y: Int),
                       direction: Direction,
                       reference: Double,
                       in buffer: PixelSampling) -> Bool {
        let move = step(direction)
        for offset in 0 ..< runLength {
            let x = start.x + move.dx * offset
            let y = start.y + move.dy * offset
            guard x >= 0, y >= 0, x < buffer.width, y < buffer.height else { return true }
            if abs(buffer.luminance(x: x, y: y) - reference) < threshold { return false }
        }
        return true
    }

    /// The region the origin sits in, closed by the edge of the screen wherever
    /// nothing else closes it.
    ///
    /// Needing all four walks to land was the same mistake as the run length: a
    /// truthful answer thrown away for failing a test that was never the question.
    /// A full bleed dark page runs off the top and the right of the screen, so the
    /// gutter between a thumbnail and its title had a left and a right and no size
    /// at all, and X said nothing where it had the number in hand. The screen edge
    /// closes a region the way a boundary does, which is what the rest of the app
    /// already believes: a drag clips onto it like any other edge.
    ///
    /// Four walks finding nothing is still nothing. That is a flat field, where
    /// there is no region under the cursor to report.
    public func bounds(around origin: (x: Int, y: Int), in buffer: PixelSampling) -> PixelRect? {
        let left = firstEdge(from: origin, direction: .left, in: buffer)
        let right = firstEdge(from: origin, direction: .right, in: buffer)
        let top = firstEdge(from: origin, direction: .up, in: buffer)
        let bottom = firstEdge(from: origin, direction: .down, in: buffer)

        guard left != nil || right != nil || top != nil || bottom != nil else { return nil }

        let x = left ?? 0
        let y = top ?? 0
        return PixelRect(x: x,
                         y: y,
                         width: (right ?? buffer.width - 1) - x + 1,
                         height: (bottom ?? buffer.height - 1) - y + 1)
    }

}
