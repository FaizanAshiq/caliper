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
