import AppKit

/// A magnified grid of the frozen frame under the cursor, so an endpoint can be landed
/// on an exact pixel. Also reads out the hex value directly under the crosshair.
final class LoupeView: NSView {
    var capturedFrame: CapturedFrame? { didSet { needsDisplay = true } }
    var centre: (x: Int, y: Int)? { didSet { needsDisplay = true } }
    var zoom: Int = 8 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    /// The loupe sits right next to the cursor, so it has to be invisible to the
    /// mouse or it would eat the drag it is there to help with.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// How many source pixels fit across the loupe at the current zoom.
    private var sourceSpan: Int { max(4, Int(bounds.width) / max(1, zoom)) }

    override func draw(_ dirtyRect: NSRect) {
        guard let capturedFrame, let centre else { return }

        let span = sourceSpan
        let half = span / 2
        let cell = bounds.width / CGFloat(span)

        for row in 0 ..< span {
            for column in 0 ..< span {
                capturedFrame.color(x: centre.x - half + column,
                                    y: centre.y - half + row).setFill()
                NSRect(x: CGFloat(column) * cell,
                       y: CGFloat(row) * cell,
                       width: cell,
                       height: cell).fill()
            }
        }

        // Pixel grid, only once the cells are big enough for it to help rather than hurt.
        if cell >= 4 {
            NSColor.white.withAlphaComponent(0.12).setStroke()
            let grid = NSBezierPath()
            grid.lineWidth = 0.5
            for step in 0 ... span {
                let offset = CGFloat(step) * cell
                grid.move(to: NSPoint(x: offset, y: 0))
                grid.line(to: NSPoint(x: offset, y: bounds.height))
                grid.move(to: NSPoint(x: 0, y: offset))
                grid.line(to: NSPoint(x: bounds.width, y: offset))
            }
            grid.stroke()
        }

        NSColor.white.setStroke()
        let target = NSBezierPath(rect: NSRect(x: CGFloat(half) * cell,
                                               y: CGFloat(half) * cell,
                                               width: cell,
                                               height: cell))
        target.lineWidth = 1
        target.stroke()

        let hex = capturedFrame.hexString(x: centre.x, y: centre.y)
        let label = NSAttributedString(string: hex, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
        let labelSize = label.size()
        let labelBox = NSRect(x: 0, y: bounds.maxY - labelSize.height - 4,
                              width: bounds.width, height: labelSize.height + 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        labelBox.fill()
        label.draw(at: NSPoint(x: (bounds.width - labelSize.width) / 2, y: labelBox.minY + 2))

        NSColor.white.withAlphaComponent(0.3).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }
}
