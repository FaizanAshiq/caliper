import AppKit
import CaliperCore

/// Draws the measurement and owns all mouse handling for one screen.
///
/// The view is flipped so that its local coordinate space has y growing downward,
/// matching CaliperCore. This is the single boundary where AppKit's y-grows-upward
/// screen space is left behind, and nothing below this line should flip again.
///
/// All the reshaping rules live in DrawingSession, which is pure and tested. This
/// view is the translator from AppKit events into calls on it.
final class CanvasView: NSView {
    var onDismiss: (() -> Void)?

    private let preferences: Preferences
    private let screenID: CGDirectDisplayID
    private let scale: Scale
    private let formatter: UnitFormatter
    private let hud = HUDView()
    private let loupe = LoupeView()
    private let shortcuts = ShortcutsView()
    private var frozenFrame: CapturedFrame?

    var onRequestResample: (() -> Void)?
    /// Handed upwards rather than done here, because the strip has to disappear on
    /// every display at once and the choice has to outlive the overlay.
    var onToggleShortcuts: (() -> Void)?

    private var session: DrawingSession?
    private var snappedBox: BoxRect?
    private var snappedGaps: [Direction: Double] = [:]
    /// Where the user clicked before there was a frame to read. Held so the snap can
    /// finish itself the moment one arrives, rather than the click being swallowed.
    private var pendingSnap: Point?
    /// What the shape is currently caught on, so it can be drawn. Without this the
    /// clipping is invisible and indistinguishable from the shape not moving smoothly.
    private var clipLines: (vertical: Double?, horizontal: Double?) = (nil, nil)
    private var isConstrained = false
    private var isFromCentre = false
    /// Command turns the clipping off, so a shape being moved goes exactly where the
    /// mouse goes instead of catching on nearby edges.
    private var isFreeMove = false
    /// Whether the user wants the strip at all, separately from whether it is being
    /// held back for the duration of a drag.
    private var shortcutsWanted = true
    /// True only between mouse down and mouse up. Once the button is released the
    /// measurement is finished, and letting go of shift afterwards must not reshape
    /// the line that is already sitting on screen with a number attached to it.
    private var isDrawing = false

    /// Carbon virtual key codes used by the canvas.
    private enum Key {
        static let escape: UInt16 = 53
        static let space: UInt16 = 49
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
        static let g: UInt16 = 5
        static let h: UInt16 = 4
        static let m: UInt16 = 46
        static let r: UInt16 = 15
    }

    /// What the next drag draws. Switching it leaves the current shape alone.
    private var pendingShape: DrawingSession.Shape = .line

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect,
         backingScaleFactor: CGFloat,
         preferences: Preferences,
         screenID: CGDirectDisplayID) {
        self.preferences = preferences
        self.screenID = screenID
        self.scale = Scale(factor: Double(backingScaleFactor))
        self.formatter = UnitFormatter(scale: scale, showBackingPixels: preferences.showBackingPixels)
        super.init(frame: frame)

        hud.frame = bounds
        hud.autoresizingMask = [.width, .height]
        addSubview(hud)

        loupe.frame = NSRect(x: 0, y: 0, width: 160, height: 160)
        loupe.zoom = preferences.loupeZoom
        loupe.isHidden = true
        addSubview(loupe)

        // Added last so it draws over the loupe rather than under it, on the rare
        // occasion the cursor is down at the bottom of the screen.
        shortcutsWanted = preferences.showShortcuts
        shortcuts.isHidden = !shortcutsWanted
        addSubview(shortcuts)
    }

    override func layout() {
        super.layout()
        shortcuts.reflow(maxWidth: bounds.width * 0.75)
        shortcuts.setFrameOrigin(NSPoint(x: (bounds.width - shortcuts.frame.width) / 2,
                                         y: bounds.maxY - shortcuts.frame.height - 32))
    }

    /// Called for every canvas when the strip is toggled on any one of them.
    func setShortcuts(visible: Bool) {
        shortcutsWanted = visible
        updateShortcuts()
    }

    private func updateShortcuts() {
        shortcuts.isHidden = isDrawing || !shortcutsWanted
    }

    /// Nil means the display could not be read, which is the normal state until the
    /// screen permission is granted. Everything that needs pixels stays hidden.
    func apply(frozenFrame: CapturedFrame?) {
        self.frozenFrame = frozenFrame
        loupe.isHidden = !canShowLoupe

        if frozenFrame != nil, let point = pendingSnap {
            pendingSnap = nil
            snap(at: point)
            refreshHUD()
        }

        needsDisplay = true
    }

    /// The cursor has to be followed with no button held, which needs a tracking area.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeAlways, .mouseMoved, .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        positionLoupe(at: localPoint(event))
    }

    /// The loupe is the colour tool and a shape is the measuring tool. Showing both
    /// at once put the magnifier on top of the reading it was competing with, and it
    /// also made Cmd+C ambiguous. Only one of them is ever on screen.
    private var canShowLoupe: Bool {
        frozenFrame != nil && !isDrawing && session == nil && snappedBox == nil
    }

    private func positionLoupe(at point: Point) {
        guard canShowLoupe, let frozenFrame else {
            loupe.isHidden = true
            return
        }
        loupe.isHidden = false
        loupe.capturedFrame = frozenFrame
        // Points to backing pixels, because the frame was read at the display's own
        // scale factor rather than in points.
        loupe.centre = (x: Int(scale.backing(fromPoints: point.x)),
                        y: Int(scale.backing(fromPoints: point.y)))

        var origin = NSPoint(x: point.x + 24, y: point.y + 24)
        if origin.x + loupe.frame.width > bounds.maxX { origin.x = point.x - loupe.frame.width - 24 }
        if origin.y + loupe.frame.height > bounds.maxY { origin.y = point.y - loupe.frame.height - 24 }
        loupe.setFrameOrigin(origin)
    }

    required init?(coder: NSCoder) {
        fatalError("CanvasView is created in code only")
    }

    private var detector: EdgeDetector {
        EdgeDetector(threshold: preferences.edgeThreshold, runLength: 3)
    }

    private func localPoint(_ event: NSEvent) -> Point {
        let location = convert(event.locationInWindow, from: nil)
        return Point(x: Double(location.x), y: Double(location.y))
    }

    private func currentMouseLocation() -> Point {
        let inWindow = window?.mouseLocationOutsideOfEventStream ?? .zero
        let local = convert(inWindow, from: nil)
        return Point(x: Double(local.x), y: Double(local.y))
    }

    override func mouseDown(with event: NSEvent) {
        snappedBox = nil
        snappedGaps = [:]
        pendingSnap = nil
        isDrawing = true
        // The loupe helps you find the spot, not read the answer. It cannot follow the
        // cursor during a drag anyway, because mouseMoved stops firing once a button is
        // down, so it would sit there stale on top of the readout it is covering.
        loupe.isHidden = true
        updateShortcuts()
        // Read the modifiers held at the moment of the click rather than trusting
        // what the last flagsChanged left behind, which may be from an earlier drag.
        isConstrained = event.modifierFlags.contains(.shift)
        isFromCentre = event.modifierFlags.contains(.option)
        isFreeMove = event.modifierFlags.contains(.command)
        session = DrawingSession(shape: pendingShape, anchor: localPoint(event))
        refreshHUD()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        session?.move(to: localPoint(event))
        updateClipping()
        refreshHUD()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        session?.move(to: localPoint(event))
        isDrawing = false
        clearClipLines()
        positionLoupe(at: localPoint(event))
        updateShortcuts()

        // Under 3 points of travel reads as a click rather than a drag.
        if let session, session.line(constrained: false).distance < 3 {
            self.session = nil
            snap(at: localPoint(event))
        }

        refreshHUD()
        needsDisplay = true
    }

    /// Clicking without dragging asks the frame what is under the cursor: its bounds,
    /// and the empty space between it and whatever sits either side.
    private func snap(at point: Point) {
        snappedBox = nil
        snappedGaps = [:]

        guard let frozenFrame else {
            pendingSnap = point
            return
        }

        let origin = (x: Int(scale.backing(fromPoints: point.x)),
                      y: Int(scale.backing(fromPoints: point.y)))

        guard let pixels = detector.bounds(around: origin, in: frozenFrame) else { return }

        snappedBox = BoxRect(
            origin: Point(x: scale.points(fromBacking: Double(pixels.x)),
                          y: scale.points(fromBacking: Double(pixels.y))),
            size: Size(width: scale.points(fromBacking: Double(pixels.width)),
                       height: scale.points(fromBacking: Double(pixels.height))))

        for direction in Direction.allCases {
            guard let gap = detector.gap(from: origin, direction: direction, in: frozenFrame) else { continue }
            snappedGaps[direction] = scale.points(fromBacking: Double(gap))
        }
    }

    /// Shift and option are read live, so the shape reshapes the moment they are held
    /// rather than on the next mouse move.
    override func flagsChanged(with event: NSEvent) {
        guard isDrawing else { return }
        isConstrained = event.modifierFlags.contains(.shift)
        isFromCentre = event.modifierFlags.contains(.option)
        isFreeMove = event.modifierFlags.contains(.command)
        updateClipping()
        refreshHUD()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case Key.escape:
            if session != nil || snappedBox != nil {
                clearDrawing()
            } else {
                onDismiss?()
            }
        case Key.space:
            // isARepeat guards against key repeat restarting the move on every tick.
            if !event.isARepeat, session?.isMoving == false {
                session?.beginMoving(from: currentMouseLocation())
            }
        case Key.h:
            onToggleShortcuts?()
        case Key.m:
            pendingShape = pendingShape == .line ? .box : .line
        case Key.g:
            if event.modifierFlags.contains(.shift) {
                GuideStore.shared.clear()
            } else {
                dropGuide()
            }
            needsDisplay = true
        case Key.r:
            onRequestResample?()
        case Key.left, Key.right, Key.up, Key.down:
            let amount: Double = event.modifierFlags.contains(.shift) ? 10 : 1
            switch event.keyCode {
            case Key.left:  session?.nudge(dx: -amount, dy: 0)
            case Key.right: session?.nudge(dx: amount, dy: 0)
            case Key.up:    session?.nudge(dx: 0, dy: -amount)
            default:        session?.nudge(dx: 0, dy: amount)
            }
            refreshHUD()
            needsDisplay = true
        default:
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
                copyCurrentValue()
                return
            }
            super.keyDown(with: event)
        }
    }

    /// Escape gets you back to an empty overlay before it gets you out of one, which
    /// is also the only way back to the loupe once something has been measured.
    private func clearDrawing() {
        session = nil
        snappedBox = nil
        snappedGaps = [:]
        clearClipLines()
        refreshHUD()
        positionLoupe(at: currentMouseLocation())
        needsDisplay = true
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == Key.space {
            session?.endMoving()
            clearClipLines()
        }
    }

    /// The dashed lines say what the shape is catching on right now. Once it stops
    /// moving it is not catching on anything, so leaving them up would read as the
    /// shape still being stuck to an edge it is free of.
    private func clearClipLines() {
        guard clipLines.vertical != nil || clipLines.horizontal != nil else { return }
        clipLines = (nil, nil)
        needsDisplay = true
    }

    /// While a shape is being moved with space, clip its edges onto anything nearby:
    /// the guides, the edges of the screen, and the element under the cursor. Holding
    /// command turns it off. The offset is recomputed from scratch on every move, so
    /// moving away from an edge releases the shape instead of dragging the clip along.
    private func updateClipping() {
        session?.setSnapOffset(dx: 0, dy: 0)
        clipLines = (nil, nil)

        guard let current = session, current.isMoving, !isFreeMove else { return }

        let xs: [Double]
        let ys: [Double]
        let probes: [Point]

        switch current.shape {
        case .box:
            let box = current.box(constrained: isConstrained, fromCentre: isFromCentre)
            let right = box.origin.x + box.size.width
            let bottom = box.origin.y + box.size.height
            xs = [box.origin.x, right]
            ys = [box.origin.y, bottom]
            probes = [Point(x: box.origin.x, y: box.origin.y), Point(x: right, y: box.origin.y),
                      Point(x: box.origin.x, y: bottom), Point(x: right, y: bottom)]
        case .line:
            let line = current.line(constrained: isConstrained)
            xs = [line.start.x, line.end.x]
            ys = [line.start.y, line.end.y]
            probes = [line.start, line.end]
        }

        let candidates = clipCandidates(probing: probes)
        let horizontalClip = Snapping.adjustment(for: xs, candidates: candidates.verticals)
        let verticalClip = Snapping.adjustment(for: ys, candidates: candidates.horizontals)

        clipLines = (vertical: horizontalClip?.candidate, horizontal: verticalClip?.candidate)
        session?.setSnapOffset(dx: horizontalClip?.delta ?? 0, dy: verticalClip?.delta ?? 0)
    }

    /// Everything the shape is allowed to clip onto: the screen edges, your guides, and
    /// the elements the shape's own corners are sitting over.
    ///
    /// Probing the corners rather than the pointer is the whole difference between
    /// catching on what you are dragging towards and catching on whatever the mouse
    /// happened to be over. While a shape is being moved the pointer sits at one corner
    /// of it, so the old reading offered edges from that corner alone and the other
    /// three had nothing to land on.
    private func clipCandidates(probing probes: [Point]) -> (verticals: [Double], horizontals: [Double]) {
        var verticals: [Double] = [0, Double(bounds.maxX)]
        var horizontals: [Double] = [0, Double(bounds.maxY)]

        for guide in GuideStore.shared.guides(for: screenID) {
            switch guide.axis {
            case .vertical: verticals.append(guide.position)
            case .horizontal: horizontals.append(guide.position)
            }
        }

        guard let frozenFrame else { return (verticals, horizontals) }

        for probe in probes {
            let origin = (x: Int(scale.backing(fromPoints: probe.x)),
                          y: Int(scale.backing(fromPoints: probe.y)))
            guard let pixels = detector.bounds(around: origin, in: frozenFrame) else { continue }
            verticals.append(scale.points(fromBacking: Double(pixels.x)))
            verticals.append(scale.points(fromBacking: Double(pixels.x + pixels.width)))
            horizontals.append(scale.points(fromBacking: Double(pixels.y)))
            horizontals.append(scale.points(fromBacking: Double(pixels.y + pixels.height)))
        }

        return (verticals, horizontals)
    }

    private func dropGuide() {
        let point = currentMouseLocation()
        // A vertical guide is the common case when pointing at a column edge, so
        // vertical wins unless the option key asks for horizontal.
        let axis: Guide.Axis = NSEvent.modifierFlags.contains(.option) ? .horizontal : .vertical
        let position = axis == .vertical ? point.x : point.y
        GuideStore.shared.add(Guide(axis: axis, position: position, screenID: screenID))
    }

    /// One copy key for whatever is on screen. A shape and the loupe are never both
    /// showing, so there is never a question of which one this means.
    private func copyCurrentValue() {
        if let snappedBox {
            copy(formatter.clipboard(box: snappedBox, format: preferences.copyFormat))
            return
        }

        guard let session else {
            copyColour()
            return
        }

        switch session.shape {
        case .line:
            copy(formatter.clipboard(line: session.line(constrained: isConstrained),
                                     format: preferences.copyFormat))
        case .box:
            copy(formatter.clipboard(box: session.box(constrained: isConstrained,
                                                      fromCentre: isFromCentre),
                                     format: preferences.copyFormat))
        }
    }

    /// The hex under the crosshair. The loupe has always shown it and nothing could
    /// ever take it anywhere.
    private func copyColour() {
        guard let frozenFrame else {
            // The screen has never been read, so there is no colour to hand over.
            NSSound.beep()
            return
        }
        let point = currentMouseLocation()
        copy(frozenFrame.hexString(x: Int(scale.backing(fromPoints: point.x)),
                                   y: Int(scale.backing(fromPoints: point.y))))
        // Picking a colour is a one shot errand: having it is the end of it. A
        // measurement is not, because you may still want to nudge it or copy it again.
        onDismiss?()
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func refreshHUD() {
        if let snappedBox {
            var parts = [formatter.display(box: snappedBox)]
            if let left = snappedGaps[.left] { parts.append("left \(formatter.display(points: left))") }
            if let right = snappedGaps[.right] { parts.append("right \(formatter.display(points: right))") }
            hud.text = parts.joined(separator: "  ")
            hud.anchor = NSPoint(x: snappedBox.origin.x + snappedBox.size.width,
                                 y: snappedBox.origin.y)
            return
        }

        guard let session else {
            hud.text = ""
            return
        }
        switch session.shape {
        case .line:
            let line = session.line(constrained: isConstrained)
            hud.text = formatter.display(line: line)
            hud.anchor = NSPoint(x: line.end.x, y: line.end.y)
        case .box:
            let box = session.box(constrained: isConstrained, fromCentre: isFromCentre)
            hud.text = formatter.display(box: box)
            hud.anchor = NSPoint(x: box.origin.x + box.size.width,
                                 y: box.origin.y + box.size.height)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // A near transparent wash, so the overlay catches clicks and reads as active
        // without obscuring what is being measured.
        NSColor.black.withAlphaComponent(0.03).setFill()
        bounds.fill()

        let guideColor = NSColor(hex: preferences.guideColorHex) ?? .systemBlue
        guideColor.withAlphaComponent(0.85).setStroke()
        for guide in GuideStore.shared.guides(for: screenID) {
            let path = NSBezierPath()
            path.lineWidth = 1
            if guide.axis == .vertical {
                path.move(to: NSPoint(x: guide.position, y: 0))
                path.line(to: NSPoint(x: guide.position, y: bounds.maxY))
            } else {
                path.move(to: NSPoint(x: 0, y: guide.position))
                path.line(to: NSPoint(x: bounds.maxX, y: guide.position))
            }
            path.stroke()
        }

        if clipLines.vertical != nil || clipLines.horizontal != nil {
            let clipColor = NSColor(hex: preferences.guideColorHex) ?? .systemBlue
            clipColor.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1
            path.setLineDash([4, 3], count: 2, phase: 0)
            if let x = clipLines.vertical {
                path.move(to: NSPoint(x: x, y: 0))
                path.line(to: NSPoint(x: x, y: bounds.maxY))
            }
            if let y = clipLines.horizontal {
                path.move(to: NSPoint(x: 0, y: y))
                path.line(to: NSPoint(x: bounds.maxX, y: y))
            }
            path.stroke()
        }

        if let snappedBox {
            let rect = NSRect(x: snappedBox.origin.x, y: snappedBox.origin.y,
                              width: snappedBox.size.width, height: snappedBox.size.height)
            let snapColor = NSColor(hex: preferences.guideColorHex) ?? .systemBlue
            snapColor.setStroke()
            let outline = NSBezierPath(rect: rect)
            outline.lineWidth = 1
            outline.stroke()
            snapColor.withAlphaComponent(0.10).setFill()
            rect.fill()
        }

        guard let session else { return }
        let color = NSColor(hex: preferences.lineColorHex) ?? .systemRed

        switch session.shape {
        case .line:
            let line = session.line(constrained: isConstrained)
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1
            path.move(to: NSPoint(x: line.start.x, y: line.start.y))
            path.line(to: NSPoint(x: line.end.x, y: line.end.y))
            path.stroke()
            // End caps, so the exact endpoints are visible against busy content.
            for end in [line.start, line.end] {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: end.x - 2, y: end.y - 2, width: 4, height: 4)).fill()
            }
        case .box:
            let box = session.box(constrained: isConstrained, fromCentre: isFromCentre)
            let rect = NSRect(x: box.origin.x, y: box.origin.y,
                              width: box.size.width, height: box.size.height)
            color.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 1
            path.stroke()
            color.withAlphaComponent(0.08).setFill()
            rect.fill()
        }
    }
}
