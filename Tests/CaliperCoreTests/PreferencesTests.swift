import Foundation
import Testing
@testable import CaliperCore

@Test("defaults bind the hotkey to control shift M")
func defaultHotkey() {
    let defaults = Preferences.defaults
    #expect(defaults.hotkey.keyCode == 46)
    #expect(defaults.hotkey.modifiers == [.control, .shift])
}

@Test("a partial file fills every missing key from defaults")
func partialDecode() throws {
    let json = Data("""
    { "showBackingPixels": false }
    """.utf8)
    let loaded = try JSONDecoder().decode(Preferences.self, from: json)
    #expect(loaded.showBackingPixels == false)
    #expect(loaded.loupeZoom == Preferences.defaults.loupeZoom)
    #expect(loaded.copyFormat == Preferences.defaults.copyFormat)
    #expect(loaded.hotkey.keyCode == 46)
}

@Test("an empty file yields pure defaults")
func emptyDecode() throws {
    let loaded = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
    #expect(loaded == Preferences.defaults)
}

@Test("preferences round trip through disk")
func roundTrip() throws {
    var prefs = Preferences.defaults
    prefs.loupeZoom = 12
    prefs.copyFormat = .css

    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("caliper-test-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }

    try prefs.save(to: url)
    let reloaded = try Preferences.load(from: url)
    #expect(reloaded == prefs)
}

@Test("a missing file loads defaults instead of throwing")
func missingFile() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("caliper-absent-\(UUID().uuidString).json")
    #expect(try Preferences.load(from: url) == Preferences.defaults)
}

@Test("a binding reads as the keys you actually press")
func hotkeyDisplay() {
    #expect(Preferences.defaults.hotkey.displayString == "⌃⇧M")
    #expect(HotKeyBinding(keyCode: 8, modifiers: [.command]).displayString == "⌘C")
    #expect(HotKeyBinding(keyCode: 49, modifiers: [.option, .command]).displayString == "⌥⌘Space")
}

@Test("modifiers read in the order macOS prints them, whatever order they are stored")
func hotkeyModifierOrder() {
    let stored = HotKeyBinding(keyCode: 46, modifiers: [.shift, .control])
    #expect(stored.displayString == "⌃⇧M")
}

@Test("an unknown key code still produces something readable")
func hotkeyUnknownKey() {
    #expect(HotKeyBinding(keyCode: 250, modifiers: []).displayString == "Key 250")
}
