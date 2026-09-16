import AppKit
import CaliperCore

/// A short stack of standard controls. Anything not exposed here is still reachable by
/// editing preferences.json, which is why this window stays small on purpose.
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private var preferences: Preferences
    private let onChange: (Preferences) -> Void

    private let backingPixelsCheckbox = NSButton(checkboxWithTitle: "Show backing pixels", target: nil, action: nil)
    private let zoomSlider = NSSlider(value: 8, minValue: 2, maxValue: 24, target: nil, action: nil)
    private let formatPopUp = NSPopUpButton()
    private let thresholdSlider = NSSlider(value: 0.12, minValue: 0.02, maxValue: 0.5, target: nil, action: nil)
    private let hotKeyRecorder: HotKeyRecorderView
    private let screenAccessButton = NSButton(title: "", target: nil, action: nil)

    init(preferences: Preferences, onChange: @escaping (Preferences) -> Void) {
        self.preferences = preferences
        self.onChange = onChange
        self.hotKeyRecorder = HotKeyRecorderView(binding: preferences.hotkey)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "Caliper Settings"
        super.init(window: window)
        window.delegate = self

        buildLayout()
        loadValues()
    }

    required init?(coder: NSCoder) {
        fatalError("PreferencesWindowController is created in code only")
    }

    private func buildLayout() {
        formatPopUp.addItems(withTitles: ["Value", "CSS"])

        let rows: [(String, NSView)] = [
            ("Measure hotkey", hotKeyRecorder),
            ("Screen recording", screenAccessButton),
            ("", backingPixelsCheckbox),
            ("Loupe zoom", zoomSlider),
            ("Copy as", formatPopUp),
            ("Edge sensitivity", thresholdSlider),
        ]

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        for (label, control) in rows {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 10
            if !label.isEmpty {
                let text = NSTextField(labelWithString: label)
                text.alignment = .right
                text.widthAnchor.constraint(equalToConstant: 120).isActive = true
                row.addArrangedSubview(text)
            }
            control.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
            row.addArrangedSubview(control)
            stack.addArrangedSubview(row)
        }

        for control in [backingPixelsCheckbox, zoomSlider, formatPopUp, thresholdSlider] as [NSControl] {
            control.target = self
            control.action = #selector(valueChanged)
        }

        screenAccessButton.target = self
        screenAccessButton.action = #selector(requestScreenAccess)
        screenAccessButton.bezelStyle = .rounded

        hotKeyRecorder.onRecord = { [weak self] binding in
            guard let self else { return }
            self.preferences.hotkey = binding
            self.persist()
        }

        window?.contentView = stack
    }

    /// The button doubles as the readout, so there is one place that says whether the
    /// screen can be read and one place to do something about it.
    private func refreshScreenAccess() {
        let granted = ScreenSampler.isAuthorised
        screenAccessButton.title = granted ? "Granted" : "Enable in System Settings"
        screenAccessButton.isEnabled = !granted
    }

    @objc private func requestScreenAccess() {
        ScreenSampler.requestAccess()
        refreshScreenAccess()
    }

    private func loadValues() {
        refreshScreenAccess()
        hotKeyRecorder.binding = preferences.hotkey
        backingPixelsCheckbox.state = preferences.showBackingPixels ? .on : .off
        zoomSlider.doubleValue = Double(preferences.loupeZoom)
        formatPopUp.selectItem(at: preferences.copyFormat == .value ? 0 : 1)
        thresholdSlider.doubleValue = preferences.edgeThreshold
    }

    @objc private func valueChanged() {
        preferences.showBackingPixels = backingPixelsCheckbox.state == .on
        preferences.loupeZoom = Int(zoomSlider.doubleValue.rounded())
        preferences.copyFormat = formatPopUp.indexOfSelectedItem == 0 ? .value : .css
        preferences.edgeThreshold = thresholdSlider.doubleValue
        persist()
    }

    private func persist() {
        // The overlay writes showShortcuts when someone presses H, possibly while this
        // window is open. Saving a copy taken when the window opened would undo that.
        if let onDisk = try? Preferences.load(from: Preferences.defaultFileURL) {
            preferences.showShortcuts = onDisk.showShortcuts
        }
        try? preferences.save(to: Preferences.defaultFileURL)
        onChange(preferences)
    }

    /// The controller outlives the window, so every opening shows the same recorder
    /// view. One left recording would reopen still listening and rebind the hotkey to
    /// whatever was typed next.
    func windowWillClose(_ notification: Notification) {
        hotKeyRecorder.stopRecording()
    }

    func show() {
        refreshScreenAccess()
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
