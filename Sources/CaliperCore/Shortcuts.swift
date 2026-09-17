import Foundation

/// One entry in the list of what the overlay responds to.
///
/// Two places show this list: the menu bar, which has room for a sentence, and the
/// strip along the bottom of the overlay, which has room for two or three words. Both
/// read it from here so that changing a key cannot leave one of them lying.
public struct Shortcut: Equatable, Sendable {
    /// How the keys print, for example "⇧", "⌘C", or "drag" when there is no key.
    public let keys: String
    /// What it does, short enough for the overlay strip.
    public let action: String
    /// The same thing as a sentence, for the menu.
    public let detail: String
    /// Which block of the menu it belongs to. Blocks are separated by a line.
    public let group: Int

    public init(keys: String, action: String, detail: String, group: Int) {
        self.keys = keys
        self.action = action
        self.detail = detail
        self.group = group
    }
}

public enum Shortcuts {
    public static let all: [Shortcut] = [
        Shortcut(keys: "drag", action: "measure",
                 detail: "Drag to measure a line", group: 0),
        Shortcut(keys: "click", action: "element",
                 detail: "Click to snap to what is under the cursor", group: 0),
        Shortcut(keys: "hover", action: "colour",
                 detail: "The loupe reads the colour under the cursor whenever nothing is drawn",
                 group: 0),
        Shortcut(keys: "M", action: "line or box",
                 detail: "Press M to switch what the next drag draws", group: 0),
        Shortcut(keys: "X", action: "gaps across",
                 detail: "Press X to show the gap left and right of whatever the cursor is over",
                 group: 0),
        Shortcut(keys: "Y", action: "gaps down",
                 detail: "Press Y to show the gap above and below whatever the cursor is over",
                 group: 0),

        Shortcut(keys: "⇧", action: "constrain",
                 detail: "Hold shift to constrain to 45 degrees", group: 1),
        Shortcut(keys: "⌥", action: "from centre",
                 detail: "Hold option to draw a box from its centre", group: 1),
        Shortcut(keys: "␣", action: "move",
                 detail: "Hold space to move the whole shape rather than resize it", group: 1),
        Shortcut(keys: "⌘", action: "no clipping",
                 detail: "Shapes clip onto guides, screen edges and the element under them. Hold command to ignore that",
                 group: 1),
        Shortcut(keys: "↑↓←→", action: "nudge",
                 detail: "Arrow keys nudge by 1 point, with shift by 10", group: 1),

        Shortcut(keys: "G", action: "guide",
                 detail: "Press G to drop a guide, or option G for a horizontal one", group: 2),
        Shortcut(keys: "⇧G", action: "clear guides",
                 detail: "Press shift G to clear every guide", group: 2),

        Shortcut(keys: "R", action: "re-read",
                 detail: "Press R to re-read the screen", group: 3),
        Shortcut(keys: "⌘C", action: "copy",
                 detail: "Press command C to copy the measurement, or the colour when the loupe is showing, which also closes the overlay", group: 3),
        Shortcut(keys: "H", action: "hide these",
                 detail: "Press H to hide this list on the overlay", group: 3),
        Shortcut(keys: "⎋", action: "clear or dismiss",
                 detail: "Press escape to clear what is drawn, then again to dismiss", group: 3),
    ]

    /// The list split into its blocks, in order, for anything that draws a separator
    /// between them.
    public static var groups: [[Shortcut]] {
        let numbers = Set(all.map(\.group)).sorted()
        return numbers.map { number in all.filter { $0.group == number } }
    }
}
