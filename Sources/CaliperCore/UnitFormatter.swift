import Foundation

public enum CopyFormat: String, Sendable, Codable {
    case value
    case css
}

public struct UnitFormatter: Sendable {
    public var scale: Scale
    public var showBackingPixels: Bool

    public init(scale: Scale, showBackingPixels: Bool) {
        self.scale = scale
        self.showBackingPixels = showBackingPixels
    }

    /// Trims a trailing .0 so whole values read as "16" rather than "16.0",
    /// while half points keep their decimal.
    private func number(_ value: Double) -> String {
        let snapped = Scale.roundedToHalfPoint(value)
        if snapped == snapped.rounded() {
            return String(Int(snapped))
        }
        return String(format: "%.1f", snapped)
    }

    public func display(points value: Double) -> String {
        let primary = "\(number(value)) pt"
        guard showBackingPixels else { return primary }
        let pixels = scale.backing(fromPoints: Scale.roundedToHalfPoint(value))
        return "\(primary) · \(number(pixels)) px"
    }

    /// Just the value, with no units, for a label drawn in a space too small to spell
    /// them out. A gap label sits beside the gap it measures, which can be eight points.
    public func compact(points value: Double) -> String {
        number(value)
    }

    public func display(box: BoxRect) -> String {
        "\(number(box.size.width)) × \(number(box.size.height)) pt"
    }

    public func display(line: LineMeasurement) -> String {
        "\(number(line.distance)) pt · dx \(number(line.dx)) · dy \(number(line.dy))"
    }

    public func clipboard(box: BoxRect, format: CopyFormat) -> String {
        switch format {
        case .value:
            return "\(number(box.size.width)) × \(number(box.size.height))"
        case .css:
            return "width: \(number(box.size.width))px; height: \(number(box.size.height))px;"
        }
    }

    /// Gap readings for the clipboard, for example "left 24  right 40". Labelled
    /// because a bare pair of numbers does not say which side is which.
    public func clipboard(gaps: [(label: String, points: Double)]) -> String {
        gaps.map { "\($0.label) \(number($0.points))" }.joined(separator: "  ")
    }

    public func clipboard(line: LineMeasurement, format: CopyFormat) -> String {
        switch format {
        case .value:
            return number(line.distance)
        case .css:
            return "\(number(line.distance))px"
        }
    }
}
