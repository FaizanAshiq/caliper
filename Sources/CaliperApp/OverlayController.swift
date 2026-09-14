import AppKit
import CaliperCore

/// A borderless window refuses to become key, which would leave the canvas unable to
/// hear escape, the arrow keys or Cmd+C. Overriding this is the whole reason the
/// overlay uses a subclass rather than a plain NSWindow.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Owns one transparent window per display. Windows join every Space so the overlay
/// is available over full screen apps as well as the desktop.
@MainActor
final class OverlayController {
    private var windows: [NSWindow] = []
    private var preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    var isArmed: Bool { !windows.isEmpty }

    func update(preferences: Preferences) {
        self.preferences = preferences
    }

    func toggle() {
        isArmed ? disarm() : arm()
    }

    func arm() {
        disarm()

        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame,
                                       styleMask: .borderless,
                                       backing: .buffered,
                                       defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true

            let canvas = CanvasView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                    backingScaleFactor: screen.backingScaleFactor,
                                    preferences: preferences)
            canvas.onDismiss = { [weak self] in self?.disarm() }

            window.contentView = canvas
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(canvas)

            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func disarm() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }
}
