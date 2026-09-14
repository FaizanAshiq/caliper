import AppKit
import CaliperCore

/// Draws the measurement and owns all mouse handling for one screen.
///
/// The view is flipped so that its local coordinate space has y growing downward,
/// matching CaliperCore. This is the single boundary where AppKit's y-grows-upward
/// screen space is left behind, and nothing below this line should flip again.
///
/// All the reshaping rules live in DrawingSession, which is pure and tested. This
/// view is the translator from AppKit events into calls on it.
final class CanvasView: NSView {
    var onDismiss: (() -> Void)?

    private let preferences: Preferences
    private let scale: Scale
    private let formatter: UnitFormatter
    private let hud = HUDView()

    private var session: DrawingSession?
    private var isConstrained = false
    private var isFromCentre = false

    /// Carbon virtual key codes used by the canvas.
    private enum Key {
        static let escape: UInt16 = 53
        static let space: UInt16 = 49
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
    }

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

    private func localPoint(_ event: NSEvent) -> Point {
        let location = convert(event.locationInWindow, from: nil)
        return Point(x: Double(location.x), y: Double(location.y))
    }

    private func currentMouseLocation() -> Point {
        let inWindow = window?.mouseLocationOutsideOfEventStream ?? .zero
        let local = convert(inWindow, from: nil)
        return Point(x: Double(local.x), y: Double(local.y))
    }

    override func mouseDown(with event: NSEvent) {
        session = DrawingSession(shape: .line, anchor: localPoint(event))
        refreshHUD()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        session?.move(to: localPoint(event))
        refreshHUD()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        session?.move(to: localPoint(event))
        refreshHUD()
        needsDisplay = true
    }

    /// Shift and option are read live, so the shape reshapes the moment they are held
    /// rather than on the next mouse move.
    override func flagsChanged(with event: NSEvent) {
        isConstrained = event.modifierFlags.contains(.shift)
        isFromCentre = event.modifierFlags.contains(.option)
        refreshHUD()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case Key.escape:
            onDismiss?()
        case Key.space:
            // isARepeat guards against key repeat restarting the move on every tick.
            if !event.isARepeat, session?.isMoving == false {
                session?.beginMoving(from: currentMouseLocation())
            }
        case Key.left, Key.right, Key.up, Key.down:
            let amount: Double = event.modifierFlags.contains(.shift) ? 10 : 1
            switch event.keyCode {
            case Key.left:  session?.nudge(dx: -amount, dy: 0)
            case Key.right: session?.nudge(dx: amount, dy: 0)
            case Key.up:    session?.nudge(dx: 0, dy: -amount)
            default:        session?.nudge(dx: 0, dy: amount)
            }
            refreshHUD()
            needsDisplay = true
        default:
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
                copyCurrentValue()
                return
            }
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == Key.space {
            session?.endMoving()
        }
    }

    private func copyCurrentValue() {
        guard let session else { return }
        let text = formatter.clipboard(line: session.line(constrained: isConstrained),
                                       format: preferences.copyFormat)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func refreshHUD() {
        guard let session else {
            hud.text = ""
            return
        }
        let line = session.line(constrained: isConstrained)
        hud.text = formatter.display(line: line)
        hud.anchor = NSPoint(x: line.end.x, y: line.end.y)
    }

    override func draw(_ dirtyRect: NSRect) {
        // A near transparent wash, so the overlay catches clicks and reads as active
        // without obscuring what is being measured.
        NSColor.black.withAlphaComponent(0.03).setFill()
        bounds.fill()

        guard let session else { return }
        let line = session.line(constrained: isConstrained)

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
