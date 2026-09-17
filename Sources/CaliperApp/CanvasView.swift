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

    /// Why there is no frozen frame, so the overlay can say what to do about it instead
    /// of quietly dropping half its features. Never asked and asked but refused need
    /// different answers, and the refused case is the one that looks like a bug.
    enum ScreenAccess {
        case granted
        case notAsked
        case blocked
    }

    var screenAccess: ScreenAccess = .granted

    var onRequestResample: (() -> Void)?
    /// Handed upwards rather than done here, because the strip has to disappear on
    /// every display at once and the choice has to outlive the overlay.
    var onToggleShortcuts: (() -> Void)?

    private var session: DrawingSession?

    /// The empty run between an element and the next one along, as the two coordinates
    /// it spans. A length on its own can be printed but never drawn.
    private struct Gap {
        let near: Double
        let far: Double
        var length: Double { abs(far - near) }
    }

    /// What was read off the frozen frame around one point. Held whole rather than as
    /// loose fields because the same reading serves a live hover and a pinned click,
    /// and because a gap can only be drawn if its position travels with it.
    private struct ElementReading {
        /// Decides what the gap numbers mean, so it travels with the reading rather
        /// than being worked out again at every place that draws or copies one.
        let kind: RegionKind
        let box: BoxRect
        /// The point the frame was read at. Every gap was measured along a ray from
        /// here, so each has to be drawn along that same ray or the line will disagree
        /// with the number beside it.
        let probe: Point
        let gaps: [Direction: Gap]
    }

    private var reading: ElementReading?
    /// True once a click has fixed the reading in place, so moving the mouse no longer
    /// replaces it. A hover reading has no such claim and is redrawn on every move.
    private var isReadingPinned = false
    /// Where the user clicked before there was a frame to read. Held so the reading can
    /// finish itself the moment one arrives, rather than the click being swallowed.
    private var pendingRead: Point?

    /// Whether X and Y have been pressed. They decide which gaps are drawn and nothing
    /// else, so two flags beat inventing an axis type for them. With both off the
    /// overlay behaves exactly as it did before they existed.
    private var showsHorizontalGaps = false
    private var showsVerticalGaps = false
    private var showsGaps: Bool { showsHorizontalGaps || showsVerticalGaps }
    private var gapDirections: [Direction] {
        var directions: [Direction] = []
        if showsHorizontalGaps { directions += [.left, .right] }
        if showsVerticalGaps { directions += [.up, .down] }
        return directions
    }
    /// What the shape is currently caught on, so it can be drawn. Without this the
    /// clipping is invisible and indistinguishable from the shape not moving smoothly.
    private var clipLines: (vertical: Double?, horizontal: Double?) = (nil, nil)
    private var isConstrained = false
    private var isFromCentre = false
    /// Command turns the clipping off, so the shape goes exactly where the mouse goes
    /// instead of catching on nearby edges.
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
        static let x: UInt16 = 7
        static let y: UInt16 = 16
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
        shortcuts.accentHex = preferences.guideColorHex
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

        if frozenFrame != nil, let point = pendingRead {
            pendingRead = nil
            pinReading(at: point)
            refreshHUD()
        }

        needsDisplay = true
    }

    /// The cursor has to be followed with no button held, which needs a tracking area.
    /// cursorUpdate comes along for the crosshair below.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeAlways, .mouseMoved, .cursorUpdate, .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
    }

    /// An arrow pointer on a measuring tool is a lie about where the reading is taken
    /// from: its tip is off to one side of the hotspot. The crosshair is centred on it.
    /// Set two ways because a borderless window at screen saver level does not always
    /// get the cursor rect applied on its own.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = localPoint(event)
        positionLoupe(at: point)
        updateHoverReading(at: point)
    }

    /// With X or Y on, the element under the cursor is read on every move so the gaps
    /// follow the pointer instead of waiting for a click. A pinned reading outranks the
    /// hover: having clicked something, you want it to stay still while you read it.
    private func updateHoverReading(at point: Point) {
        guard showsGaps, !isReadingPinned, !isDrawing else { return }
        reading = read(at: point)
        refreshHUD()
        needsDisplay = true
    }

    /// The loupe is the colour tool and a shape is the measuring tool. Showing both
    /// at once put the magnifier on top of the reading it was competing with, and it
    /// also made Cmd+C ambiguous. Only one of them is ever on screen. X and Y take the
    /// hover for the gaps, which is the same argument a third time.
    private var canShowLoupe: Bool {
        frozenFrame != nil && !isDrawing && session == nil && !isReadingPinned && !showsGaps
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
        reading = nil
        isReadingPinned = false
        pendingRead = nil
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
        // Clip where the drag actually finished and then make it permanent. The number
        // on screen when the button comes up is the one about to be copied.
        updateClipping()
        session?.commitCursorClip()
        isDrawing = false
        clearClipLines()
        updateShortcuts()

        // Under 3 points of travel reads as a click rather than a drag.
        if let session, session.line(constrained: false).distance < 3 {
            self.session = nil
            pinReading(at: localPoint(event))
        }

        // After the reading, so a click that found nothing hands the hover back to the
        // loupe rather than leaving the overlay with nothing on it.
        positionLoupe(at: localPoint(event))
        refreshHUD()
        needsDisplay = true
    }

    /// Clicking without dragging fixes the reading in place, so it survives the mouse
    /// moving off and can be copied at leisure.
    private func pinReading(at point: Point) {
        reading = nil
        isReadingPinned = false

        guard frozenFrame != nil else {
            pendingRead = point
            return
        }

        reading = read(at: point)
        isReadingPinned = reading != nil
    }

    /// Asks the frame what is under a point: the element's bounds, and where the empty
    /// space between it and whatever sits each way runs from and to.
    private func read(at point: Point) -> ElementReading? {
        guard let frozenFrame else { return nil }

        let origin = (x: Int(scale.backing(fromPoints: point.x)),
                      y: Int(scale.backing(fromPoints: point.y)))

        guard let pixels = detector.bounds(around: origin, in: frozenFrame) else { return nil }

        var gaps: [Direction: Gap] = [:]
        for direction in Direction.allCases {
            guard let span = detector.gapSpan(from: origin, direction: direction, in: frozenFrame) else { continue }
            gaps[direction] = Gap(near: scale.points(fromBacking: Double(span.near)),
                                  far: scale.points(fromBacking: Double(span.far)))
        }

        let box = BoxRect(origin: Point(x: scale.points(fromBacking: Double(pixels.x)),
                                       y: scale.points(fromBacking: Double(pixels.y))),
                         size: Size(width: scale.points(fromBacking: Double(pixels.width)),
                       height: scale.points(fromBacking: Double(pixels.height))))

        return ElementReading(
            kind: RegionKind.of(box, onScreen: Size(width: Double(bounds.width),
                                                    height: Double(bounds.height))),
            box: box,
            probe: point,
            gaps: gaps)
    }

    /// One drawn span: the axis it lies along, the run it covers, and the word it
    /// copies as. Held together so the drawing and the clipboard cannot disagree about
    /// which gaps are worth showing.
    private struct Span {
        let horizontal: Bool
        let gap: Gap
        /// left, right, up or down for a thing, width or height for a space.
        let label: String
    }

    /// What X and Y actually draw, as a span along one axis each.
    ///
    /// For a thing, the gaps to its neighbours. For a space, the space's own width and
    /// height, because when you point at a gutter its width is the measurement you came
    /// for and the width of the card beyond it is not.
    private func spans(of reading: ElementReading) -> [Span] {
        var result: [Span] = []

        switch reading.kind {
        case .space:
            if showsHorizontalGaps {
                result.append(Span(horizontal: true,
                                   gap: Gap(near: reading.box.origin.x,
                                            far: reading.box.origin.x + reading.box.size.width),
                                   label: "width"))
            }
            if showsVerticalGaps {
                result.append(Span(horizontal: false,
                                   gap: Gap(near: reading.box.origin.y,
                                            far: reading.box.origin.y + reading.box.size.height),
                                   label: "height"))
            }
        case .thing:
            for direction in gapDirections {
                guard let gap = reading.gaps[direction] else { continue }
                result.append(Span(horizontal: direction == .left || direction == .right,
                                   gap: gap,
                                   label: Self.name(of: direction)))
            }
        }

        return result.filter { $0.gap.length > Self.hairline }
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
            if session != nil || isReadingPinned {
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
            needsDisplay = true
        case Key.x:
            showsHorizontalGaps.toggle()
            gapsChanged()
        case Key.y:
            showsVerticalGaps.toggle()
            gapsChanged()
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

    /// Turning the gaps on takes the hover away from the loupe and gives it to the
    /// element under the cursor. Turning the last one off hands it straight back, so
    /// neither tool is left waiting for a mouse move to notice the mode changed.
    private func gapsChanged() {
        let point = currentMouseLocation()
        if !showsGaps, !isReadingPinned { reading = nil }
        // X and Y are modes with nothing else on screen to say they are on, so the
        // strip lights their own entries up.
        var lit: Set<String> = []
        if showsHorizontalGaps { lit.insert("X") }
        if showsVerticalGaps { lit.insert("Y") }
        shortcuts.activeKeys = lit
        updateHoverReading(at: point)
        positionLoupe(at: point)
        refreshHUD()
        needsDisplay = true
    }

    /// Escape gets you back to an empty overlay before it gets you out of one, which
    /// is also the only way back to the loupe once something has been measured.
    private func clearDrawing() {
        session = nil
        reading = nil
        isReadingPinned = false
        pendingRead = nil
        clearClipLines()
        let point = currentMouseLocation()
        updateHoverReading(at: point)
        positionLoupe(at: point)
        refreshHUD()
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

    /// Clip the shape onto anything nearby: the guides, the edges of the screen, and
    /// the elements under it. On every drag, not only while space is held, because
    /// landing on the edge you were aiming at is what makes the reading worth trusting.
    /// Holding command turns it off. The offset is recomputed from scratch on every
    /// move, so moving away from an edge releases the shape instead of dragging the
    /// clip along behind it.
    private func updateClipping() {
        session?.setSnapOffset(dx: 0, dy: 0)
        session?.setCursorClip(dx: 0, dy: 0)
        clipLines = (nil, nil)

        guard let current = session, !isFreeMove else { return }

        if current.isMoving {
            clipWholeShape(current)
        } else if isDrawing {
            clipLooseEnd(current)
        }
    }

    /// While the shape is being drawn, only the end under the cursor clips. The anchor
    /// stays where the mouse went down: space is how you move a point you have already
    /// placed, and clipping it from here would move it behind your back.
    private func clipLooseEnd(_ current: DrawingSession) {
        var end = current.cursor
        var clipsX = true
        var clipsY = true

        // Shift is a precision constraint of its own and it is applied after the clip,
        // so clipping the axis the line is pinned on would land it just off the
        // candidate it had caught. Only the free axis clips. A squared box clips on
        // neither, because squaring rederives both sides from whichever is longer.
        if isConstrained {
            switch current.shape {
            case .box:
                return
            case .line:
                let line = current.line(constrained: true)
                end = line.end
                clipsX = line.dy == 0 && line.dx != 0
                clipsY = line.dx == 0 && line.dy != 0
            }
        }

        guard clipsX || clipsY else { return }

        let candidates = clipCandidates(probing: [end])
        let horizontalClip = clipsX
            ? Snapping.adjustment(for: [end.x], candidates: candidates.verticals) : nil
        let verticalClip = clipsY
            ? Snapping.adjustment(for: [end.y], candidates: candidates.horizontals) : nil

        clipLines = (vertical: horizontalClip?.candidate, horizontal: verticalClip?.candidate)
        session?.setCursorClip(dx: horizontalClip?.delta ?? 0, dy: verticalClip?.delta ?? 0)
    }

    /// Holding space moves the shape whole, so every one of its edges is a candidate for
    /// clipping and the offset lands on both ends at once.
    private func clipWholeShape(_ current: DrawingSession) {
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
        if let reading {
            if showsGaps, let gaps = gapClipboard(of: reading) {
                copy(gaps)
                return
            }
            copy(formatter.clipboard(box: reading.box, format: preferences.copyFormat))
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

    /// The gaps on screen, labelled, because a bare pair of numbers does not say which
    /// side is which. Nil when nothing was found either way, so the element's own size
    /// gets copied rather than an empty string.
    private func gapClipboard(of reading: ElementReading) -> String? {
        let drawn = spans(of: reading)
        guard !drawn.isEmpty else { return nil }
        // Exactly what is on screen, in the same order, because copying something the
        // overlay is not showing is worse than copying nothing.
        return formatter.clipboard(gaps: drawn.map { (label: $0.label, points: $0.gap.length) })
    }

    private static func name(of direction: Direction) -> String {
        switch direction {
        case .left: return "left"
        case .right: return "right"
        case .up: return "up"
        case .down: return "down"
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
        // The gaps carry their own labels, drawn on the gaps themselves, so the readout
        // stays the element's own size rather than repeating four numbers already on
        // screen a few points away.
        if let reading {
            hud.text = formatter.display(box: reading.box)
            hud.anchor = NSPoint(x: reading.box.origin.x + reading.box.size.width,
                                 y: reading.box.origin.y)
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

    /// Says why the loupe, the gap readings and element snapping are missing. Only ever
    /// on screen when there is no frame, and silent while a fresh read is still in
    /// flight, so arming does not flash a warning that is about to be untrue.
    private var screenNote: String? {
        guard frozenFrame == nil else { return nil }
        switch screenAccess {
        case .granted:
            return nil
        case .notAsked:
            return "Screen Recording is off. The loupe, the X and Y gaps and element snapping need it."
        case .blocked:
            return "macOS is refusing to hand over the screen. Switch Caliper off and on again in Screen Recording settings."
        }
    }

    /// A gap no bigger than this is a border, not spacing.
    ///
    /// Readings stop at half a point, and half a point and one point are the two widths
    /// a hairline rule comes in. Walking up out of a table row lands on the one point
    /// line between it and the row above, and labelling that is a truthful answer to a
    /// question nobody asked: a tick and a pill on screen to describe a border. The
    /// tightest spacing anyone sets on purpose is wider than this.
    private static let hairline: Double = 1

    /// How far a tick reaches either side of the gap line, and how far the label sits
    /// off it. A gap can be eight points wide, so the label goes beside the line rather
    /// than in it, where a pill would cover the very thing it is measuring.
    private static let tickReach: CGFloat = 5
    private static let labelReach: CGFloat = 17

    /// Each gap is drawn along the ray it was measured on, with a tick at both ends and
    /// the number beside it. Running the line through the middle of the element instead
    /// would put it somewhere the measurement never went.
    private func drawGaps(of reading: ElementReading) {
        let color = NSColor(hex: preferences.lineColorHex) ?? .systemRed

        for span in spans(of: reading) {
            let (horizontal, gap) = (span.horizontal, span.gap)
            let start = horizontal ? NSPoint(x: gap.near, y: reading.probe.y)
                                   : NSPoint(x: reading.probe.x, y: gap.near)
            let end = horizontal ? NSPoint(x: gap.far, y: reading.probe.y)
                                 : NSPoint(x: reading.probe.x, y: gap.far)

            let path = NSBezierPath()
            path.lineWidth = 1
            path.move(to: start)
            path.line(to: end)
            // Ticks across both ends, so a gap narrower than its own label is still
            // visibly bounded by the two edges it was measured between.
            for point in [start, end] {
                if horizontal {
                    path.move(to: NSPoint(x: point.x, y: point.y - Self.tickReach))
                    path.line(to: NSPoint(x: point.x, y: point.y + Self.tickReach))
                } else {
                    path.move(to: NSPoint(x: point.x - Self.tickReach, y: point.y))
                    path.line(to: NSPoint(x: point.x + Self.tickReach, y: point.y))
                }
            }
            color.setStroke()
            path.stroke()

            let middle = NSPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let label = horizontal ? NSPoint(x: middle.x, y: middle.y - Self.labelReach)
                                   : NSPoint(x: middle.x + Self.labelReach, y: middle.y)
            // The axis goes in the label. Four gaps drawn in one colour with bare
            // numbers were four of the same thing, and with only one axis on there was
            // nothing to say which one you were looking at.
            drawPill("\(horizontal ? "↔" : "↕") \(formatter.compact(points: gap.length))",
                     centredAt: label)
        }
    }

    /// A gap label, in the same dark pill the readout uses. Drawn here rather than
    /// through HUDView because four can be on screen at once and each one belongs to a
    /// gap of its own rather than to the cursor.
    private func drawPill(_ text: String, centredAt centre: NSPoint) {
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
        let size = string.size()
        let padding: CGFloat = 5
        let box = NSRect(x: centre.x - size.width / 2 - padding,
                         y: centre.y - size.height / 2 - padding,
                         width: size.width + padding * 2,
                         height: size.height + padding * 2)
        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        string.draw(at: NSPoint(x: box.minX + padding, y: box.minY + padding))
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

        if let reading {
            let snapColor = NSColor(hex: preferences.guideColorHex) ?? .systemBlue

            // Outlining a space is what made a cursor resting in a gutter paint a tall
            // blue column over half the screen. The span line says everything the
            // outline would, and says it about the thing being measured.
            if !(showsGaps && reading.kind == .space) {
                let rect = NSRect(x: reading.box.origin.x, y: reading.box.origin.y,
                                  width: reading.box.size.width, height: reading.box.size.height)
                snapColor.setStroke()
                let outline = NSBezierPath(rect: rect)
                outline.lineWidth = 1
                outline.stroke()
                snapColor.withAlphaComponent(0.10).setFill()
                rect.fill()
            }

            if showsGaps {
                drawGaps(of: reading)
                // Every gap was measured along a ray from this point, so showing it is
                // the difference between trusting the numbers and guessing at them.
                snapColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: reading.probe.x - 2.5, y: reading.probe.y - 2.5,
                                            width: 5, height: 5)).fill()
            }
        }

        if let screenNote {
            drawPill(screenNote, centredAt: NSPoint(x: bounds.midX, y: 44))
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
