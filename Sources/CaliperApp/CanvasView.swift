import AppKit
import CaliperCore

/// Draws the measurement and owns all mouse handling for one screen.
///
/// The view is flipped so that its local coordinate space has y growing downward,
/// matching CaliperCore. This is the single boundary where AppKit's y-grows-upward
/// screen space is left behind, and nothing below this line should flip again.
final class CanvasView: NSView {
    var onDismiss: (() -> Void)?

    private let preferences: Preferences
    private let scale: Scale
    private let formatter: UnitFormatter
    private let hud = HUDView()

    private var dragStart: Point?
    private var dragCurrent: Point?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, backingScaleFactor: CGFloat, preferences: Preferences) {
        self.preferences = preferences
        self.scale = Scale(factor: Double(backingScaleFactor))
        self.formatter = UnitFormatter(scale: scale, showBackingPixels: preferences.showBackingPixels)
        super.init(frame: frame)

        hud.frame = bounds
        hud.autoresizingMask = [.width, .height]
        addSubview(hud)
    }

    required init?(coder: NSCoder) {
        fatalError("CanvasView is created in code only")
    }

    private var currentLine: LineMeasurement? {
        guard let dragStart, let dragCurrent else { return nil }
        return LineMeasurement(start: dragStart, end: dragCurrent)
    }

    private func localPoint(_ event: NSEvent) -> Point {
        let location = convert(event.locationInWindow, from: nil)
        return Point(x: Double(location.x), y: Double(location.y))
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = localPoint(event)
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = localPoint(event)
        refreshHUD()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragCurrent = localPoint(event)
        refreshHUD()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        // 53 is escape.
        if event.keyCode == 53 {
            onDismiss?()
            return
        }
        super.keyDown(with: event)
    }

    private func refreshHUD() {
        guard let line = currentLine else {
            hud.text = ""
            return
        }
        hud.text = formatter.display(line: line)
        hud.anchor = NSPoint(x: line.end.x, y: line.end.y)
    }

    override func draw(_ dirtyRect: NSRect) {
        // A near transparent wash, so the overlay catches clicks and reads as active
        // without obscuring what is being measured.
        NSColor.black.withAlphaComponent(0.03).setFill()
        bounds.fill()

        guard let line = currentLine else { return }

        let color = NSColor(hex: preferences.lineColorHex) ?? .systemRed
        color.setStroke()

        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: NSPoint(x: line.start.x, y: line.start.y))
        path.line(to: NSPoint(x: line.end.x, y: line.end.y))
        path.stroke()

        // End caps, so the exact endpoints are visible against busy content.
        for end in [line.start, line.end] {
            let dot = NSRect(x: end.x - 2, y: end.y - 2, width: 4, height: 4)
            color.setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
    }
}
