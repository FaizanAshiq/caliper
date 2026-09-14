import AppKit

extension NSColor {
    /// Parses a six digit RGB hex string with no leading marker, for example "FF3B30".
    convenience init?(hex: String) {
        var value: UInt64 = 0
        guard hex.count == 6, Scanner(string: hex).scanHexInt64(&value) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}
