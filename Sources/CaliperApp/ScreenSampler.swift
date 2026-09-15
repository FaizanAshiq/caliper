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

    /// Pays the one off ScreenCaptureKit setup cost at launch.
    ///
    /// The first call after launch takes several seconds to bring the service up.
    /// Until it returns there is no frame, so the loupe stays hidden and a click that
    /// should snap silently does nothing, with no way for the user to tell why. Doing
    /// it once at launch makes the first arm as quick as every one after it. It reads
    /// no pixels, only the list of shareable displays, and it is skipped entirely
    /// without permission so nothing is ever prompted.
    func warmUp() async {
        guard Self.isAuthorised else { return }
        _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
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
