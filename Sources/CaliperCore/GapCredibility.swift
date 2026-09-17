import Foundation

/// Which measured gaps are worth putting on screen.
///
/// The gap walk is arithmetic over whatever the edge detector found, and it is honest
/// about that: it cannot tell a real run of empty space from one that ran straight
/// through an edge it failed to see. Both ends of the range give that away.
///
/// Too small and it is a border. Too large and it is the page. In between is spacing,
/// which is the only thing anyone pressed X or Y to find out.
public enum GapCredibility {
    /// At or under this, the gap is a rule rather than spacing.
    ///
    /// Readings stop at half a point, and half a point and one point are the two widths
    /// a hairline comes in. Walking up out of a table row lands on the one point line
    /// between it and the row above, and labelling that is a truthful answer to a
    /// question nobody asked.
    public static let hairline: Double = 1

    /// Above this fraction of the screen along the axis, the gap is the page.
    ///
    /// The same ratio RegionKind uses to tell a thing from the space around it, for the
    /// same reason, so the two cannot drift apart. A card on a light page whose own
    /// background is within the luminance threshold of that page has no edge the
    /// detector can see, so a gap measured towards it runs past it and on to whatever
    /// differs next, which may be most of the way down the screen. Spacing between two
    /// things in one layout is never that.
    public static let pageRatio: Double = RegionKind.spaceRatio

    /// `screenSpan` is the screen's size along the axis the gap runs on. Zero or less
    /// means the screen is not known yet, which only suppresses the ceiling rather than
    /// rejecting everything.
    public static func isSpacing(_ length: Double,
                                 screenSpan: Double,
                                 ratio: Double = pageRatio) -> Bool {
        guard length > hairline else { return false }
        guard screenSpan > 0 else { return true }
        return length <= screenSpan * ratio
    }
}
