import AppKit
import ScreenCaptureKit

extension NSScreen {
    /// The display id AppKit keeps in deviceDescription. The guide store, the sampler
    /// and the capture filter all key off it, so it is written out once here.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Holds one frozen frame per display.
///
/// The frame is taken once when the overlay arms and is reused for every lookup until
/// the user asks for a fresh one. This keeps the cost at zero while measuring and stops
/// edge detection flickering when something behind the overlay animates.
@MainActor
final class ScreenSampler {
    private var frames: [CGDirectDisplayID: CapturedFrame] = [:]

    /// Checked rather than requested, so nothing prompts the user before they actually
    /// reach for a feature that needs it.
    static var isAuthorised: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestAccess() {
        CGRequestScreenCaptureAccess()
    }

    func frame(for screenID: CGDirectDisplayID) -> CapturedFrame? {
        frames[screenID]
    }

    func clear() {
        frames.removeAll()
    }

    /// Reads every display. Failures are per display and quiet: a display that cannot
    /// be read simply has no frame, and the features needing one stay off for that
    /// display rather than taking the whole overlay down.
    func refresh() async {
        frames.removeAll()
        guard Self.isAuthorised else { return }

        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true) else { return }

        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            // SCDisplay reports points. The read has to happen at backing resolution,
            // because that is what preserves half point precision. The factor comes
            // from the display itself rather than being assumed to be 2, or every
            // reading on a 1x screen would come back doubled.
            let factor = Int(backingScaleFactor(for: display.displayID))
            configuration.width = display.width * factor
            configuration.height = display.height * factor
            configuration.captureResolution = .best
            configuration.showsCursor = false

            guard let image = try? await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: configuration),
                  let frame = CapturedFrame(cgImage: image) else { continue }

            frames[display.displayID] = frame
        }
    }

    private func backingScaleFactor(for displayID: CGDirectDisplayID) -> CGFloat {
        NSScreen.screens.first { $0.displayID == displayID }?.backingScaleFactor ?? 2
    }
}
