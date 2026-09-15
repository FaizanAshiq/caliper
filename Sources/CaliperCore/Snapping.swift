import Foundation

/// Clipping a shape onto nearby edges while it is being moved, the way a design tool
/// does. It knows nothing about where the candidates came from: the app collects them
/// from the guides, the screen edges and the element under the cursor, and this decides
/// whether any of them is close enough to be worth moving to.
public enum Snapping {
    /// How close an edge has to be before it clips, in points. Eight is what
    /// Photoshop uses and it is close enough to feel deliberate rather than magnetic.
    public static let tolerance: Double = 8

    /// The shift that brings one of `positions` onto the nearest candidate, or nil
    /// when nothing is close enough to be worth moving to. The smallest movement
    /// wins, so an edge that is already almost aligned is preferred over one that
    /// would drag the whole shape further.
    public static func adjustment(for positions: [Double],
                                  candidates: [Double],
                                  tolerance: Double = tolerance) -> Double? {
        var best: Double?

        for position in positions {
            for candidate in candidates {
                let delta = candidate - position
                guard abs(delta) <= tolerance else { continue }
                if abs(delta) < abs(best ?? .infinity) {
                    best = delta
                }
            }
        }

        return best
    }
}
