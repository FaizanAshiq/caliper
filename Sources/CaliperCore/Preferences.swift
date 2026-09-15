import Foundation

public enum ModifierKey: String, Sendable, Codable, CaseIterable {
    case control
    case option
    case shift
    case command
}

public struct HotKeyBinding: Equatable, Sendable, Codable {
    /// A Carbon virtual key code. 46 is the M key.
    public var keyCode: UInt32
    public var modifiers: [ModifierKey]

    public init(keyCode: UInt32, modifiers: [ModifierKey]) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// The binding written the way macOS prints it in a menu, for example "⌃⇧M".
    /// Modifiers always appear in the system order regardless of how they were
    /// stored, because a hand edited preferences file can list them any way round.
    public var displayString: String {
        let systemOrder: [(ModifierKey, String)] = [
            (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
        ]
        let symbols = systemOrder
            .filter { modifiers.contains($0.0) }
            .map(\.1)
            .joined()
        return symbols + Self.label(for: keyCode)
    }

    /// The character a menu item needs as its key equivalent, or an empty string for
    /// a key that has no single character, such as space or an arrow.
    public var keyEquivalent: String {
        let label = Self.label(for: keyCode)
        return label.count == 1 ? label.lowercased() : ""
    }

    /// Carbon virtual key codes. Only the keys worth binding a hotkey to, because
    /// anything missing still reads as "Key 250" rather than as nothing at all.
    private static let labels: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    private static func label(for keyCode: UInt32) -> String {
        labels[keyCode] ?? "Key \(keyCode)"
    }
}

public struct Preferences: Equatable, Sendable, Codable {
    public var hotkey: HotKeyBinding
    public var showBackingPixels: Bool
    public var lineColorHex: String
    public var guideColorHex: String
    public var loupeZoom: Int
    public var copyFormat: CopyFormat
    /// Luminance difference, 0 to 1, that counts as an element boundary.
    public var edgeThreshold: Double

    public static let defaults = Preferences(
        hotkey: HotKeyBinding(keyCode: 46, modifiers: [.control, .shift]),
        showBackingPixels: true,
        lineColorHex: "FF3B30",
        guideColorHex: "0A84FF",
        loupeZoom: 8,
        copyFormat: .value,
        edgeThreshold: 0.12
    )

    public init(hotkey: HotKeyBinding,
                showBackingPixels: Bool,
                lineColorHex: String,
                guideColorHex: String,
                loupeZoom: Int,
                copyFormat: CopyFormat,
                edgeThreshold: Double) {
        self.hotkey = hotkey
        self.showBackingPixels = showBackingPixels
        self.lineColorHex = lineColorHex
        self.guideColorHex = guideColorHex
        self.loupeZoom = loupeZoom
        self.copyFormat = copyFormat
        self.edgeThreshold = edgeThreshold
    }

    /// Every key is optional on the way in so that a file written by an older
    /// version, or a hand edited partial file, still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Preferences.defaults
        hotkey = try container.decodeIfPresent(HotKeyBinding.self, forKey: .hotkey) ?? fallback.hotkey
        showBackingPixels = try container.decodeIfPresent(Bool.self, forKey: .showBackingPixels) ?? fallback.showBackingPixels
        lineColorHex = try container.decodeIfPresent(String.self, forKey: .lineColorHex) ?? fallback.lineColorHex
        guideColorHex = try container.decodeIfPresent(String.self, forKey: .guideColorHex) ?? fallback.guideColorHex
        loupeZoom = try container.decodeIfPresent(Int.self, forKey: .loupeZoom) ?? fallback.loupeZoom
        copyFormat = try container.decodeIfPresent(CopyFormat.self, forKey: .copyFormat) ?? fallback.copyFormat
        edgeThreshold = try container.decodeIfPresent(Double.self, forKey: .edgeThreshold) ?? fallback.edgeThreshold
    }

    public static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Caliper/preferences.json")
    }

    /// Returns defaults when the file does not exist, so first launch needs no setup.
    public static func load(from url: URL) throws -> Preferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return .defaults }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Preferences.self, from: data)
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
