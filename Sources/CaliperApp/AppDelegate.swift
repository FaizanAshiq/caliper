import AppKit
import CaliperCore

/// Everything here touches AppKit, which is main thread only. Swift 6 does not
/// infer that from the delegate conformance, so it is stated once on the class.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeyMonitor: HotKeyMonitor?
    private var overlay: OverlayController?
    private var preferencesWindow: PreferencesWindowController?
    var preferences: Preferences = .defaults

    /// Whether the app could read the screen when it started. Granting the permission
    /// flips the system check straight away, but ScreenCaptureKit keeps failing until
    /// the app restarts, so this is what tells the difference between "not granted"
    /// and "granted, but this copy of the app cannot use it yet".
    private var couldReadScreenAtLaunch = false
    private var hasOfferedScreenAccess = false
    /// Set by the two places that have already dealt with coming back, or decided not
    /// to, so the terminate hook below does not launch a second copy behind them.
    private var suppressRelaunchOnQuit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        couldReadScreenAtLaunch = ScreenSampler.isAuthorised
        reloadPreferences()
        installStatusItem()
        overlay = OverlayController(preferences: preferences)
        overlay?.warmUp()

        let monitor = HotKeyMonitor { [weak self] in
            self?.requestOverlay()
        }
        monitor.register(preferences.hotkey)
        hotKeyMonitor = monitor
    }

    private func toggleOverlay() {
        overlay?.toggle()
    }

    func reloadPreferences() {
        preferences = (try? Preferences.load(from: Preferences.defaultFileURL)) ?? .defaults
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "ruler", accessibilityDescription: "Caliper")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        statusItem = item
    }

    /// Rebuilt every time the menu opens rather than once at launch, so the setup row
    /// disappears the moment the permission is granted and the hotkey shown always
    /// matches the preferences file.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Preflight says yes and every capture still comes back empty. Nothing the app
        // can do about it, so offer the one place the user can.
        if overlay?.isScreenBlocked == true {
            menu.addItem(NSMenuItem(title: "Fix Screen Recording",
                                    action: #selector(openScreenRecordingSettings),
                                    keyEquivalent: ""))
            menu.addItem(note("macOS still lists Caliper but is handing over nothing"))
            menu.addItem(NSMenuItem.separator())
        }

        if ScreenSampler.isAuthorised, !couldReadScreenAtLaunch {
            menu.addItem(NSMenuItem(title: "Restart Caliper to Finish Enabling",
                                    action: #selector(restart),
                                    keyEquivalent: ""))
            menu.addItem(note("macOS only lets an app read the screen after a restart"))
            menu.addItem(NSMenuItem.separator())
        }

        menu.addItem(NSMenuItem(title: "Measure  \(preferences.hotkey.displayString)",
                                action: #selector(toggleOverlayFromMenu),
                                keyEquivalent: ""))

        let shortcuts = NSMenuItem(title: "Shortcuts", action: nil, keyEquivalent: "")
        shortcuts.submenu = buildShortcutsMenu()
        menu.addItem(shortcuts)
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Clear Guides", action: #selector(clearGuides), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Caliper", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
    }

    /// A line of explanation rather than something to click.
    private func note(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        return item
    }

    /// System Settings offers a Quit and Reopen button that does not reliably bring a
    /// menu bar only app back, which leaves the user staring at an empty menu bar
    /// after granting the permission. This starts a fresh copy first, then stands down.
    @objc private func restart() {
        suppressRelaunchOnQuit = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                           configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// A reference list, not a set of commands: every row has no action, so nothing
    /// here can be clicked or fired by accident. autoenablesItems is off so the rows
    /// read as text rather than as a menu full of unavailable options. The rows come
    /// from CaliperCore, the same list the overlay strip draws.
    private func buildShortcutsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(title: "While the overlay is open", action: nil, keyEquivalent: ""))

        for group in Shortcuts.groups {
            menu.addItem(NSMenuItem.separator())
            for shortcut in group {
                menu.addItem(NSMenuItem(title: shortcut.detail, action: nil, keyEquivalent: ""))
            }
        }

        return menu
    }

    /// The permission is already granted as far as TCC is concerned, so requesting it
    /// again returns instantly and changes nothing. Toggling the row by hand is the only
    /// thing that clears it.
    @objc private func openScreenRecordingSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleOverlayFromMenu() {
        requestOverlay()
    }

    /// The one way in, whichever way you came. Asked for at the point of use rather
    /// than sitting in the menu as a chore, and once per launch, so declining it is not
    /// punished with the same box every time.
    ///
    /// The hotkey used to call toggleOverlay directly and skip all of this, which meant
    /// the way almost everyone opens the overlay was the one way that never mentioned
    /// the permission. It came up looking fine with the loupe, the gap readings and
    /// element snapping all silently dead, and nothing on screen saying why.
    private func requestOverlay() {
        if !ScreenSampler.isAuthorised, !hasOfferedScreenAccess {
            hasOfferedScreenAccess = true

            let alert = NSAlert()
            alert.messageText = "Caliper measures without any permission"
            alert.informativeText = "The loupe, the eyedropper, the X and Y gap readings and snapping onto an element all read what is on screen, so they need Screen Recording. The ruler, the marquee, guides and snapping to a guide or a screen edge do not."
            alert.addButton(withTitle: "Enable")
            alert.addButton(withTitle: "Not Now")
            NSApp.activate(ignoringOtherApps: true)

            if alert.runModal() == .alertFirstButtonReturn {
                ScreenSampler.requestAccess()
                return
            }
        }

        toggleOverlay()
    }

    /// Changes take effect on the next arm rather than mid measurement, which is why
    /// the overlay is handed the new values rather than rebuilt.
    @objc private func showPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController(preferences: preferences) { [weak self] updated in
                self?.preferences = updated
                self?.overlay?.update(preferences: updated)
                self?.hotKeyMonitor?.register(updated.hotkey)
            }
        }
        preferencesWindow?.show()
    }

    @objc private func clearGuides() {
        GuideStore.shared.clear()
    }

    @objc private func quit() {
        suppressRelaunchOnQuit = true
        NSApp.terminate(nil)
    }

    /// Something other than our own Quit item is ending this run, and the screen became
    /// readable while it was going. That is System Settings' Quit and Reopen button,
    /// and its reopen half frequently does not bring a menu bar only app back: the icon
    /// vanishes and the permission that was just granted looks broken. The menu offers
    /// a restart row for the same reason, but that only helps someone still running.
    /// So bring a fresh copy up first, and stand down once it is there.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !suppressRelaunchOnQuit, ScreenSampler.isAuthorised, !couldReadScreenAtLaunch else {
            return .terminateNow
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                           configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        // Quitting still has to happen if the launch never reports back, or the app
        // hangs on the way out instead of reappearing on the way in.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
