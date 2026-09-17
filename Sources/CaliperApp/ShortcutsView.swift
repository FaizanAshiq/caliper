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

    /// Keys currently holding a mode open, drawn lit rather than dim. X and Y have
    /// nothing else on screen to say they are on, and a mode you cannot see is a mode
    /// you will leave on by accident.
    var activeKeys: Set<String> = [] {
        didSet {
            guard activeKeys != oldValue else { return }
            needsDisplay = true
        }
    }

    /// Matches the guides, so the lit state is the same colour everywhere it appears.
    var accentHex: String = "0A84FF" { didSet { needsDisplay = true } }

    private static let gap: CGFloat = 16
    private let padding: CGFloat = 10
    private let lineGap: CGFloat = 4

    private var rows: [[Shortcut]] = []
    private var lineHeight: CGFloat = 14

    private static let keyFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    private static let actionFont = NSFont.systemFont(ofSize: 11)

    /// Lit and dim differ only in colour, never in font, so a label is the same width
    /// either way and turning a mode on can never force the strip to repack.
    private func label(for shortcut: Shortcut) -> NSAttributedString {
        let lit = activeKeys.contains(shortcut.keys)
        let accent = NSColor(hex: accentHex) ?? .systemBlue
        let text = NSMutableAttributedString(string: shortcut.keys, attributes: [
            .font: Self.keyFont,
            .foregroundColor: lit ? accent : NSColor.white,
        ])
        text.append(NSAttributedString(string: " " + shortcut.action, attributes: [
            .font: Self.actionFont,
            .foregroundColor: lit ? accent : NSColor.white.withAlphaComponent(0.6),
        ]))
        return text
    }

    /// Packs the list into as few rows as fit the width, then sizes itself to match.
    func reflow(maxWidth: CGFloat) {
        lineHeight = Shortcuts.all.first.map { label(for: $0).size().height } ?? 14

        let limit = maxWidth - padding * 2
        var packed: [[Shortcut]] = []
        var row: [Shortcut] = []
        var width: CGFloat = 0

        for shortcut in Shortcuts.all {
            let size = label(for: shortcut).size().width
            let next = row.isEmpty ? size : width + Self.gap + size
            if !row.isEmpty, next > limit {
                packed.append(row)
                row = [shortcut]
                width = size
                continue
            }
            row.append(shortcut)
            width = next
        }
        if !row.isEmpty { packed.append(row) }

        rows = packed
        let widest = packed.map(width(of:)).max() ?? 0
        let height = padding * 2
            + CGFloat(packed.count) * lineHeight
            + CGFloat(max(0, packed.count - 1)) * lineGap
        setFrameSize(NSSize(width: widest + padding * 2, height: height))
        needsDisplay = true
    }

    private func width(of row: [Shortcut]) -> CGFloat {
        row.reduce(0) { $0 + label(for: $1).size().width } + CGFloat(max(0, row.count - 1)) * Self.gap
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !rows.isEmpty else { return }

        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()

        var y = padding
        for row in rows {
            var x = (bounds.width - width(of: row)) / 2
            var previousGroup: Int?
            for shortcut in row {
                // The list already comes in blocks: what the mouse does, what the
                // modifiers do, guides, and the overlay's own commands. Sixteen entries
                // running together read as one wall, so where a block changes partway
                // along a row the rule says so.
                if let previousGroup, previousGroup != shortcut.group {
                    NSColor.white.withAlphaComponent(0.18).setFill()
                    NSRect(x: x - Self.gap / 2, y: y + 1, width: 1, height: lineHeight - 2).fill()
                }
                let label = label(for: shortcut)
                label.draw(at: NSPoint(x: x, y: y))
                x += label.size().width + Self.gap
                previousGroup = shortcut.group
            }
            y += lineHeight + lineGap
        }
    }
}
