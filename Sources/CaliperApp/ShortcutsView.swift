import AppKit
import CaliperCore

/// The strip along the bottom of the overlay that says what the keys do.
///
/// It reflows to whatever width it is given rather than hard coding rows, so the same
/// list fits a laptop display and a wide external one without being edited.
final class ShortcutsView: NSView {
    override var isFlipped: Bool { true }

    /// It covers a band across the screen, so it has to be invisible to the mouse or
    /// it would swallow measurements taken near the bottom edge.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private static let gap: CGFloat = 16
    private let padding: CGFloat = 10
    private let lineGap: CGFloat = 4

    private var rows: [[NSAttributedString]] = []
    private var lineHeight: CGFloat = 14

    private static func label(for shortcut: Shortcut) -> NSAttributedString {
        let text = NSMutableAttributedString(string: shortcut.keys, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
        text.append(NSAttributedString(string: " " + shortcut.action, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ]))
        return text
    }

    /// Packs the list into as few rows as fit the width, then sizes itself to match.
    func reflow(maxWidth: CGFloat) {
        let labels = Shortcuts.all.map(Self.label)
        lineHeight = labels.first?.size().height ?? 14

        let limit = maxWidth - padding * 2
        var packed: [[NSAttributedString]] = []
        var row: [NSAttributedString] = []
        var width: CGFloat = 0

        for label in labels {
            let next = row.isEmpty ? label.size().width : width + Self.gap + label.size().width
            if !row.isEmpty, next > limit {
                packed.append(row)
                row = [label]
                width = label.size().width
                continue
            }
            row.append(label)
            width = next
        }
        if !row.isEmpty { packed.append(row) }

        rows = packed
        let widest = packed.map(Self.width(of:)).max() ?? 0
        let height = padding * 2
            + CGFloat(packed.count) * lineHeight
            + CGFloat(max(0, packed.count - 1)) * lineGap
        setFrameSize(NSSize(width: widest + padding * 2, height: height))
        needsDisplay = true
    }

    private static func width(of row: [NSAttributedString]) -> CGFloat {
        row.reduce(0) { $0 + $1.size().width } + CGFloat(max(0, row.count - 1)) * gap
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !rows.isEmpty else { return }

        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()

        var y = padding
        for row in rows {
            var x = (bounds.width - Self.width(of: row)) / 2
            for label in row {
                label.draw(at: NSPoint(x: x, y: y))
                x += label.size().width + Self.gap
            }
            y += lineHeight + lineGap
        }
    }
}
