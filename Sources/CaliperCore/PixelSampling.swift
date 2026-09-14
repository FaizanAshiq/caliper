import Foundation

/// A rectangle in backing pixels. Distinct from BoxRect, which is in logical points,
/// so the compiler stops the two from being confused.
public struct PixelRect: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Read only access to a captured frame. Implemented by ArrayPixelBuffer in tests
/// and by the ScreenCaptureKit backed buffer in the app.
public protocol PixelSampling {
    var width: Int { get }
    var height: Int { get }
    /// Perceived brightness from 0 for black to 1 for white.
    func luminance(x: Int, y: Int) -> Double
}

public struct ArrayPixelBuffer: PixelSampling, Sendable {
    public let width: Int
    public let height: Int
    private let luminances: [Double]

    public init(width: Int, height: Int, luminances: [Double]) {
        precondition(luminances.count == width * height, "luminance count must match the buffer size")
        self.width = width
        self.height = height
        self.luminances = luminances
    }

    public func luminance(x: Int, y: Int) -> Double {
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        return luminances[y * width + x]
    }
}
