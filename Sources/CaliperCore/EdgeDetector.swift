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

    public func bounds(around origin: (x: Int, y: Int), in buffer: PixelSampling) -> PixelRect? {
        guard let left = firstEdge(from: origin, direction: .left, in: buffer),
              let right = firstEdge(from: origin, direction: .right, in: buffer),
              let top = firstEdge(from: origin, direction: .up, in: buffer),
              let bottom = firstEdge(from: origin, direction: .down, in: buffer) else {
            return nil
        }
        return PixelRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
    }

    /// The empty run between the element under the cursor and the next one along, as
    /// the pair of coordinates it spans rather than only its length.
    ///
    /// Both values are on the axis the direction runs along: x for left and right, y
    /// for up and down. Drawing a gap needs to know where it sits, and it has to be
    /// drawn along the same ray it was measured on or the line will not match the
    /// number beside it.
    public func gapSpan(from origin: (x: Int, y: Int),
                        direction: Direction,
                        in buffer: PixelSampling) -> (near: Int, far: Int)? {
        guard let near = firstEdge(from: origin, direction: direction, in: buffer) else { return nil }
        let move = step(direction)
        let horizontal = direction == .left || direction == .right

        let probeX = horizontal ? near + move.dx : origin.x
        let probeY = horizontal ? origin.y : near + move.dy
        guard probeX >= 0, probeY >= 0, probeX < buffer.width, probeY < buffer.height else { return nil }

        guard let far = firstEdge(from: (probeX, probeY), direction: direction, in: buffer) else { return nil }
        return (near: near, far: far)
    }

    /// The empty distance between the element under the cursor and the next one along.
    public func gap(from origin: (x: Int, y: Int),
                    direction: Direction,
                    in buffer: PixelSampling) -> Int? {
        guard let span = gapSpan(from: origin, direction: direction, in: buffer) else { return nil }
        return abs(span.far - span.near)
    }
}
