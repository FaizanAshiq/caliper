import AppKit

struct Guide: Equatable {
    enum Axis {
        case horizontal
        case vertical
    }

    let axis: Axis
    /// Distance in points from the top or left edge of the screen it belongs to.
    let position: Double
    let screenID: CGDirectDisplayID
}

/// Guides outlive a single overlay session, so they live here rather than in a view.
@MainActor
final class GuideStore {
    static let shared = GuideStore()

    private(set) var guides: [Guide] = []

    var onChange: (() -> Void)?

    func add(_ guide: Guide) {
        guides.append(guide)
        onChange?()
    }

    func clear() {
        guides.removeAll()
        onChange?()
    }

    func guides(for screenID: CGDirectDisplayID) -> [Guide] {
        guides.filter { $0.screenID == screenID }
    }
}

/// Draws the guides for one screen and nothing else. This is what keeps them on
/// screen once the overlay is dismissed, which is the whole point of a guide.
final class GuideView: NSView {
    var guides: [Guide] = [] { didSet { needsDisplay = true } }
    var colorHex: String = "0A84FF"

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let color = NSColor(hex: colorHex) ?? .systemBlue
        color.withAlphaComponent(0.85).setStroke()

        for guide in guides {
            let path = NSBezierPath()
            path.lineWidth = 1
            if guide.axis == .vertical {
                path.move(to: NSPoint(x: guide.position, y: 0))
                path.line(to: NSPoint(x: guide.position, y: bounds.maxY))
            } else {
                path.move(to: NSPoint(x: 0, y: guide.position))
                path.line(to: NSPoint(x: bounds.maxX, y: guide.position))
            }
            path.stroke()
        }
    }
}
