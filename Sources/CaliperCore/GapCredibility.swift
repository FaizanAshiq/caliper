import Foundation

/// Which measured spans are worth putting on screen.
public enum GapCredibility {
    /// At or under this, the region is a rule rather than a space worth naming.
    ///
    /// Readings stop at half a point, and half a point and one point are the two widths
    /// a hairline comes in. The line between two table rows is a region like any other,
    /// and labelling it is a truthful answer to a question nobody asked.
    public static let hairline: Double = 1
}
