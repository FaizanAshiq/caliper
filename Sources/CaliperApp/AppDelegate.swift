import AppKit
import CaliperCore

/// Everything here touches AppKit, which is main thread only. Swift 6 does not
/// infer that from the delegate conformance, so it is stated once on the class.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeyMonitor: HotKeyMonitor?
    private var overlay: OverlayController?
    private(set) var preferences: Preferences = .defaults

    func applicationDidFinishLaunching(_ notification: Notification) {
        reloadPreferences()
        installStatusItem()
        overlay = OverlayController(preferences: preferences)

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
        if !ScreenSampler.isAuthorised {
            menu.addItem(NSMenuItem(title: "Enable Loupe and Snapping",
                                    action: #selector(grantAccess),
                                    keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
        }
        menu.addItem(NSMenuItem(title: "Clear Guides", action: #selector(clearGuides), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Caliper", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu

        statusItem = item
    }

    /// Only ever reached from the menu, so the system prompt appears when the user
    /// actually reaches for a feature that needs it and never before.
    @objc private func grantAccess() {
        ScreenSampler.requestAccess()
    }

    @objc private func clearGuides() {
        GuideStore.shared.clear()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
