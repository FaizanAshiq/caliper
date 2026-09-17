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
    ///
    /// This reports the TCC row, not whether a capture will actually succeed. See
    /// isBlockedDespiteAuthorisation for why the difference matters.
    static var isAuthorised: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// True when a refresh ran while authorised and still came back with no frame at
    /// all. macOS keeps the TCC row against the bundle id but enforces against the
    /// signature, so resigning the app, or letting Sequoia's monthly approval lapse,
    /// leaves preflight answering yes while every capture returns nil. Trusting
    /// preflight alone put the overlay on screen with the loupe, the gap readings and
    /// element snapping all dead and nothing saying why.
    private(set) var isBlockedDespiteAuthorisation = false

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
        isBlockedDespiteAuthorisation = false
    }

    /// Reads every display. Failures are per display and quiet: a display that cannot
    /// be read simply has no frame, and the features needing one stay off for that
    /// display rather than taking the whole overlay down.
    func refresh() async {
        frames.removeAll()
        isBlockedDespiteAuthorisation = false
        guard Self.isAuthorised else { return }
        // Covers the early return below as well as the end of the loop.
        defer { isBlockedDespiteAuthorisation = frames.isEmpty }

        // onScreenWindowsOnly is false here only so that this app is certain to appear
        // in content.applications. With it true the list holds apps whose windows are
        // already composited, and the overlay is often not composited yet at this
        // point, so there was nothing named Caliper to leave out and the read kept
        // itself: two runs in three the eyedropper reported every colour 3% dark.
        // What is read is still only what is on screen.
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false) else { return }

        // The overlay paints a 3% black wash over everything so that it catches clicks,
        // and it is up by the time this runs. Including it darkened every colour the
        // eyedropper reported, and put our own guides and readout in front of the edge
        // detector as if they were things worth measuring.
        let ownApplications = content.applications.filter {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }

        for display in content.displays {
            let filter = SCContentFilter(display: display,
                                         excludingApplications: ownApplications,
                                         exceptingWindows: [])
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
            // Capture in sRGB rather than the display's own space. Without this the
            // frame arrives in P3 and CapturedFrame converts it back, and two 8 bit
            // conversions cost a couple of levels per channel: a window painted
            // #1A334D was read as #18324A. The eyedropper has to give back the value
            // that was painted, not one that has been round tripped.
            configuration.colorSpaceName = CGColorSpace.sRGB

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
