import AppKit
import CaliperCore

/// One sampled display, in backing pixels, held as raw bytes so that a luminance
/// lookup during edge detection costs an array index rather than a CoreGraphics call.
struct CapturedFrame: PixelSampling {
    let width: Int
    let height: Int
    private let bytesPerRow: Int
    private let bytes: [UInt8]

    /// The sizes are held in locals first. Reading them off self inside the closure
    /// would capture a half built value, which the compiler refuses.
    init?(cgImage: CGImage) {
        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        let rowBytes = pixelWidth * 4

        var buffer = [UInt8](repeating: 0, count: rowBytes * pixelHeight)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let drew = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress,
                                          width: pixelWidth,
                                          height: pixelHeight,
                                          bitsPerComponent: 8,
                                          bytesPerRow: rowBytes,
                                          space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            return true
        }

        guard drew else { return nil }

        width = pixelWidth
        height = pixelHeight
        bytesPerRow = rowBytes
        bytes = buffer
    }

    private func offset(x: Int, y: Int) -> Int? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return y * bytesPerRow + x * 4
    }

    /// Rec. 709 luma. Perceived brightness rather than a plain channel average, so a
    /// saturated blue button reads as dark against white the way the eye sees it.
    func luminance(x: Int, y: Int) -> Double {
        guard let index = offset(x: x, y: y) else { return 0 }
        let red = Double(bytes[index]) / 255
        let green = Double(bytes[index + 1]) / 255
        let blue = Double(bytes[index + 2]) / 255
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    func color(x: Int, y: Int) -> NSColor {
        guard let index = offset(x: x, y: y) else { return .clear }
        return NSColor(srgbRed: CGFloat(bytes[index]) / 255,
                       green: CGFloat(bytes[index + 1]) / 255,
                       blue: CGFloat(bytes[index + 2]) / 255,
                       alpha: 1)
    }

    /// Written with the hash, because that is the form every stylesheet and design
    /// tool wants and this string is both shown and copied.
    func hexString(x: Int, y: Int) -> String {
        guard let index = offset(x: x, y: y) else { return "#000000" }
        return String(format: "#%02X%02X%02X", bytes[index], bytes[index + 1], bytes[index + 2])
    }
}
