import AppKit
import CaliperCore

/// Click it, press a combination, done.
///
/// Deliberately small: it records one binding and hands it back, and knows nothing
/// about where that binding is stored or what it will be used for.
final class HotKeyRecorderView: NSView {
    var binding: HotKeyBinding { didSet { needsDisplay = true } }
    var onRecord: ((HotKeyBinding) -> Void)?

    private var isRecording = false { didSet { needsDisplay = true } }

    init(binding: HotKeyBinding) {
        self.binding = binding
        super.init(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
    }

    required init?(coder: NSCoder) {
        fatalError("HotKeyRecorderView is created in code only")
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 180, height: 24) }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    /// Stops recording without binding anything. Closing a window does not resign its
    /// first responder, so a field left armed comes back armed: showing the prompt
    /// instead of the binding, and rebinding on the next key pressed anywhere in the
    /// window. Whoever owns the window has to say when it is over.
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Escape backs out rather than binding escape itself, which would be a hotkey
        // you could never press again to change your mind.
        if event.keyCode == 53 {
            isRecording = false
            return
        }

        var modifiers: [ModifierKey] = []
        if event.modifierFlags.contains(.control) { modifiers.append(.control) }
        if event.modifierFlags.contains(.option) { modifiers.append(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.append(.shift) }
        if event.modifierFlags.contains(.command) { modifiers.append(.command) }

        // A hotkey with no modifier is registered system wide, so it would swallow
        // that key in every other app as well.
        guard !modifiers.isEmpty else {
            NSSound.beep()
            return
        }

        binding = HotKeyBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        isRecording = false
        onRecord?(binding)
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)

        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text = isRecording ? "Press a combination" : binding.displayString
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ])
        let size = string.size()
        string.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                y: (bounds.height - size.height) / 2))
    }
}
