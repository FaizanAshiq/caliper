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
