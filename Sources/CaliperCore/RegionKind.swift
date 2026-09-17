import Foundation

/// Whether the region under the cursor is a thing or the space between things.
///
/// Reading pixels cannot answer that directly: a white card on a white page and the
/// gutter between two white cards are the same colour, and neither has a name. What the
/// pixels do give is the region's shape, and the space between things has a tell. It
/// runs a long way across the screen in at least one axis, because it is the background
/// showing through, while a card, a button or a thumbnail is bounded at a plausible size
/// in both.
///
/// The distinction earns its place because the gap measurement means opposite things
/// either side of it. Walking out from a thing, the next region along is empty space, so
/// its width is the gap. Walking out from a space, the next region along is a thing, so
/// its width is that thing's width and calling it a gap is simply wrong. That is what
/// made a cursor resting in a gutter report the widths of the two cards beside it.
///
/// Getting the call wrong is cheap. Read as a space, a region reports its own width and
/// height, which for a full width hero image is still a number worth having.
public enum RegionKind: Equatable, Sendable {
    /// Something you would measure: a card, a button, an icon, an image.
    case thing
    /// Background showing between things: a gutter, a margin, the page itself.
    case space

    /// Four tenths of the screen along either axis. A gutter in a card grid runs most of
    /// the way down, and a page background runs both ways, while the largest single
    /// element anyone reaches for stays well under it.
    public static let spaceRatio: Double = 0.4

    public static func of(_ region: BoxRect,
                          onScreen screen: Size,
                          ratio: Double = spaceRatio) -> RegionKind {
        // A screen with no size is the state before the first layout. Guessing "space"
        // there would blank the reading on the very first hover.
        guard screen.width > 0, screen.height > 0 else { return .thing }

        let runsWide = region.size.width >= screen.width * ratio
        let runsTall = region.size.height >= screen.height * ratio
        return runsWide || runsTall ? .space : .thing
    }
}
