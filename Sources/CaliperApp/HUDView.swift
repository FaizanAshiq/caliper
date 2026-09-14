import AppKit

/// The floating readout that follows the cursor. Kept as a plain layer drawing view
/// rather than a child window so it cannot steal focus or lag behind the line.
final class HUDView: NSView {
    var text: String = "" { didSet { needsDisplay = true } }
    var anchor: NSPoint = .zero { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    private let padding: CGFloat = 6
    private let offset: CGFloat = 14

    /// The readout covers the whole canvas, so it has to be invisible to the mouse or
    /// it would swallow the drag that produced the measurement in the first place.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private var attributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }

        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()
        var origin = NSPoint(x: anchor.x + offset, y: anchor.y + offset)

        // Flip the readout back across the cursor when it would fall off screen.
        if origin.x + textSize.width + padding * 2 > bounds.maxX {
            origin.x = anchor.x - textSize.width - padding * 2 - offset
        }
        if origin.y + textSize.height + padding * 2 > bounds.maxY {
            origin.y = anchor.y - textSize.height - padding * 2 - offset
        }

        let box = NSRect(x: origin.x, y: origin.y,
                         width: textSize.width + padding * 2,
                         height: textSize.height + padding * 2)

        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        string.draw(at: NSPoint(x: box.minX + padding, y: box.minY + padding))
    }
}
