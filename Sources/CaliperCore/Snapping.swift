import Foundation

/// Clipping a shape onto nearby edges while it is being moved, the way a design tool
/// does. It knows nothing about where the candidates came from: the app collects them
/// from the guides, the screen edges and the element under the cursor, and this decides
/// whether any of them is close enough to be worth moving to.
public enum Snapping {
    /// A clip that is worth making: how far to move, and onto what. The canvas needs
    /// the second part so it can show the user what their shape caught on.
    public struct Clip: Equatable, Sendable {
        public let delta: Double
        public let candidate: Double

        public init(delta: Double, candidate: Double) {
            self.delta = delta
            self.candidate = candidate
        }
    }

    /// How close an edge has to be before it clips, in points. Twelve is wide enough
    /// to catch an edge you are aiming at without having to land on it, and still
    /// narrow enough that two edges a few points apart do not fight over the shape.
    public static let tolerance: Double = 12

    /// The shift that brings one of `positions` onto the nearest candidate, or nil
    /// when nothing is close enough to be worth moving to. The smallest movement
    /// wins, so an edge that is already almost aligned is preferred over one that
    /// would drag the whole shape further.
    public static func adjustment(for positions: [Double],
                                  candidates: [Double],
                                  tolerance: Double = tolerance) -> Clip? {
        var best: Clip?

        for position in positions {
            for candidate in candidates {
                let delta = candidate - position
                guard abs(delta) <= tolerance else { continue }
                if abs(delta) < abs(best?.delta ?? .infinity) {
                    best = Clip(delta: delta, candidate: candidate)
                }
            }
        }

        return best
    }
}
