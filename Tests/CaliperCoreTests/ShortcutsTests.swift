import Testing
@testable import CaliperCore

@Test("every shortcut says what it does")
func noBlankEntries() {
    for shortcut in Shortcuts.all {
        #expect(!shortcut.keys.isEmpty)
        #expect(!shortcut.action.isEmpty)
        #expect(!shortcut.detail.isEmpty)
    }
}

@Test("splitting into groups keeps every entry in order")
func groupsCoverEverything() {
    let flattened = Shortcuts.groups.flatMap { $0 }
    #expect(flattened == Shortcuts.all)
}

@Test("the key that hides the list is in the list")
func hideKeyIsDiscoverable() {
    // Nothing else on screen would tell you the strip can be dismissed, so if this
    // entry goes missing the feature becomes a one way door.
    #expect(Shortcuts.all.contains { $0.keys == "H" })
}

@Test("no two shortcuts claim the same keys")
func keysAreUnique() {
    let keys = Shortcuts.all.map(\.keys)
    #expect(Set(keys).count == keys.count)
}
