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
///
/// Guides get their own click through window per display. They are meant to survive
/// dismissing the overlay, so something has to keep drawing them once the measuring
/// canvas is gone. Only one of the two is ever on screen at a time, so a guide is
/// never drawn twice on top of itself.
@MainActor
final class OverlayController {
    private var windows: [NSWindow] = []
    private var screenIDs: [CGDirectDisplayID] = []
    private var guideWindows: [NSWindow] = []
    private var preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
        GuideStore.shared.onChange = { [weak self] in self?.guidesChanged() }
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
        hideGuideWindows()

        for screen in NSScreen.screens {
            let screenID = screen.displayID

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
                                    preferences: preferences,
                                    screenID: screenID)
            canvas.onDismiss = { [weak self] in self?.disarm() }

            window.contentView = canvas
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(canvas)

            windows.append(window)
            screenIDs.append(screenID)
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func disarm() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        screenIDs.removeAll()
        showGuideWindows()
    }

    private func guidesChanged() {
        guard isArmed else {
            showGuideWindows()
            return
        }
        for window in windows {
            window.contentView?.needsDisplay = true
        }
    }

    private func showGuideWindows() {
        hideGuideWindows()

        for screen in NSScreen.screens {
            let screenID = screen.displayID
            let guides = GuideStore.shared.guides(for: screenID)
            guard !guides.isEmpty else { continue }

            let window = NSWindow(contentRect: screen.frame,
                                  styleMask: .borderless,
                                  backing: .buffered,
                                  defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            // Click through, so a guide left on screen never gets in your way.
            window.ignoresMouseEvents = true

            let view = GuideView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.colorHex = preferences.guideColorHex
            view.guides = guides
            window.contentView = view
            window.orderFront(nil)

            guideWindows.append(window)
        }
    }

    private func hideGuideWindows() {
        for window in guideWindows {
            window.orderOut(nil)
        }
        guideWindows.removeAll()
    }
}
