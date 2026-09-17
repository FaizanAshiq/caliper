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
    private var focusObserver: NSObjectProtocol?
    private var preferences: Preferences
    private let sampler = ScreenSampler()

    init(preferences: Preferences) {
        self.preferences = preferences
        GuideStore.shared.onChange = { [weak self] in self?.guidesChanged() }
    }

    var isArmed: Bool { !windows.isEmpty }

    /// macOS says the permission is there and hands over nothing anyway. Surfaced so
    /// the menu can offer the one thing that fixes it.
    var isScreenBlocked: Bool { sampler.isBlockedDespiteAuthorisation }

    /// Called once at launch. See ScreenSampler.warmUp for why.
    func warmUp() {
        Task { @MainActor in await sampler.warmUp() }
    }

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
            canvas.onRequestResample = { [weak self] in self?.refreshFrames() }
            canvas.onToggleShortcuts = { [weak self] in self?.toggleShortcuts() }

            window.contentView = canvas
            window.setFrame(screen.frame, display: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(canvas)

            windows.append(window)
            screenIDs.append(screenID)
        }

        NSApp.activate(ignoringOtherApps: true)
        watchForLostFocus()
        refreshFrames()
    }

    /// Armed but unfocused is the worst state the overlay can be in. It covers every
    /// screen, so there is nothing behind it to click on, and without key status escape
    /// and copy do nothing: the screen is held hostage by a window that is not
    /// listening. So whatever takes the focus, take it straight back.
    ///
    /// Only the application losing it counts. Moving between our own windows on two
    /// displays resigns key on one of them, and reacting to that would have the two
    /// windows pulling focus off each other for as long as the overlay was up.
    private func watchForLostFocus() {
        focusObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isArmed else { return }
                NSApp.activate(ignoringOtherApps: true)
                let mouse = NSEvent.mouseLocation
                let window = self.windows.first { $0.frame.contains(mouse) } ?? self.windows.first
                window?.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func stopWatchingFocus() {
        guard let focusObserver else { return }
        NotificationCenter.default.removeObserver(focusObserver)
        self.focusObserver = nil
    }

    /// One display's worth of keystroke, every display's worth of effect. Written to
    /// disk as well, so turning the strip off is a decision and not a per launch chore.
    private func toggleShortcuts() {
        preferences.showShortcuts.toggle()
        try? preferences.save(to: Preferences.defaultFileURL)
        for window in windows {
            (window.contentView as? CanvasView)?.setShortcuts(visible: preferences.showShortcuts)
        }
    }

    /// Reads every display once, then hands each canvas its own frozen frame. Nothing
    /// blocks on this: the overlay is already up and usable before it finishes.
    private func refreshFrames() {
        Task { @MainActor in
            await sampler.refresh()
            let access: CanvasView.ScreenAccess = sampler.isBlockedDespiteAuthorisation ? .blocked
                : ScreenSampler.isAuthorised ? .granted : .notAsked
            for (window, screenID) in zip(windows, screenIDs) {
                let canvas = window.contentView as? CanvasView
                canvas?.screenAccess = access
                canvas?.apply(frozenFrame: sampler.frame(for: screenID))
            }
        }
    }

    func disarm() {
        // First, or ordering the windows out reads as the app losing focus and the
        // watcher hauls it back to a window that is on its way off screen.
        stopWatchingFocus()
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        screenIDs.removeAll()
        sampler.clear()
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
