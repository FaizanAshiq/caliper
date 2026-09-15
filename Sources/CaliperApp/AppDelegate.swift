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

    func applicationDidFinishLaunching(_ notification: Notification) {
        couldReadScreenAtLaunch = ScreenSampler.isAuthorised
        reloadPreferences()
        installStatusItem()
        overlay = OverlayController(preferences: preferences)
        overlay?.warmUp()

        let monitor = HotKeyMonitor { [weak self] in
            self?.toggleOverlay()
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

        if !ScreenSampler.isAuthorised {
            menu.addItem(NSMenuItem(title: "Enable Loupe and Snapping",
                                    action: #selector(grantAccess),
                                    keyEquivalent: ""))
            menu.addItem(note("Needed for the loupe, the eyedropper and snapping"))
            menu.addItem(note("Everything else already works"))
            menu.addItem(NSMenuItem.separator())
        } else if !couldReadScreenAtLaunch {
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
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL,
                                           configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// A reference list, not a set of commands: every row has no action, so nothing
    /// here can be clicked or fired by accident. autoenablesItems is off so the rows
    /// read as text rather than as a menu full of unavailable options.
    private func buildShortcutsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        func row(_ title: String, _ key: String = "", _ mask: NSEvent.ModifierFlags = []) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: key)
            item.keyEquivalentModifierMask = mask
            menu.addItem(item)
        }

        row("While the overlay is open")
        menu.addItem(NSMenuItem.separator())

        row("Drag to measure a line")
        row("Click to snap to what is under the cursor")
        row("Switch what the next drag draws", "m")
        menu.addItem(NSMenuItem.separator())

        row("Hold shift to constrain to 45 degrees")
        row("Hold space to move the shape without resizing it")
        row("While moving it clips to guides, edges and the element under it")
        row("Hold command while moving to ignore the clipping")
        row("Hold option to draw a box from its centre")
        row("Arrow keys nudge by 1 point, with shift by 10")
        menu.addItem(NSMenuItem.separator())

        row("Drop a guide", "g")
        row("Drop a horizontal guide", "g", .option)
        row("Clear every guide", "g", .shift)
        menu.addItem(NSMenuItem.separator())

        row("Re-read the screen", "r")
        row("Copy the value", "c", .command)
        row("Dismiss", "\u{1b}")

        return menu
    }

    @objc private func toggleOverlayFromMenu() {
        toggleOverlay()
    }

    /// Only ever reached from the menu, so the system prompt appears when the user
    /// actually reaches for a feature that needs it and never before.
    @objc private func grantAccess() {
        ScreenSampler.requestAccess()
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
        NSApp.terminate(nil)
    }
}
