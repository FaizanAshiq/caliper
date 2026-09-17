import Testing
@testable import CaliperCore

@Test("an edge within the tolerance clips onto the candidate")
func clipsWhenClose() {
    let clip = Snapping.adjustment(for: [103], candidates: [100], tolerance: 8)
    #expect(clip?.delta == -3)
    #expect(clip?.candidate == 100)
}

@Test("nothing clips when every candidate is too far away")
func ignoresDistantCandidates() {
    #expect(Snapping.adjustment(for: [120], candidates: [100], tolerance: 8) == nil)
}

@Test("the smallest movement wins when more than one is in range")
func prefersTheNearest() {
    // The right edge is 1 point from a candidate, the left edge is 4 from another.
    let clip = Snapping.adjustment(for: [100, 200], candidates: [104, 199], tolerance: 8)
    #expect(clip?.delta == -1)
    #expect(clip?.candidate == 199)
}

@Test("an edge already sitting on a candidate does not move")
func alreadyAligned() {
    #expect(Snapping.adjustment(for: [100], candidates: [100], tolerance: 8)?.delta == 0)
}

@Test("no candidates means no clipping")
func noCandidates() {
    #expect(Snapping.adjustment(for: [100], candidates: [], tolerance: 8) == nil)
}

@Test("a snap offset shifts the whole shape without resizing it")
func snapOffsetShifts() {
    var session = DrawingSession(shape: .box, anchor: Point(x: 0, y: 0))
    session.move(to: Point(x: 100, y: 50))
    session.setSnapOffset(dx: -3, dy: 2)

    let box = session.box(constrained: false, fromCentre: false)
    #expect(box.origin == Point(x: -3, y: 2))
    #expect(box.size == Size(width: 100, height: 50))
}

@Test("moving away from a candidate lets the shape go again")
func snapOffsetIsNotSticky() {
    var session = DrawingSession(shape: .box, anchor: Point(x: 0, y: 0))
    session.move(to: Point(x: 100, y: 50))
    session.setSnapOffset(dx: -3, dy: 2)
    session.setSnapOffset(dx: 0, dy: 0)

    #expect(session.box(constrained: false, fromCentre: false).origin == Point(x: 0, y: 0))
}

@Test("ending a move keeps the clipping it finished on")
func snapOffsetSurvivesTheMoveEnding() {
    var session = DrawingSession(shape: .box, anchor: Point(x: 0, y: 0))
    session.move(to: Point(x: 100, y: 50))
    session.beginMoving(from: Point(x: 100, y: 50))
    session.setSnapOffset(dx: -3, dy: 2)
    session.endMoving()

    let box = session.box(constrained: false, fromCentre: false)
    #expect(box.origin == Point(x: -3, y: 2))
    #expect(box.size == Size(width: 100, height: 50))
}

@Test("the default tolerance catches an edge you are near without being on it")
func defaultToleranceIsWideEnoughToAimWith() {
    #expect(Snapping.adjustment(for: [110], candidates: [100]) != nil)
    #expect(Snapping.adjustment(for: [113], candidates: [100]) == nil)
}

@Test("a cursor clip moves the loose end and leaves the anchor alone")
func cursorClipMovesOneEnd() {
    var session = DrawingSession(shape: .line, anchor: Point(x: 0, y: 0))
    session.move(to: Point(x: 100, y: 50))
    session.setCursorClip(dx: -3, dy: 2)

    let line = session.line(constrained: false)
    #expect(line.start == Point(x: 0, y: 0))
    #expect(line.end == Point(x: 97, y: 52))
}

@Test("committing a cursor clip keeps it without making it sticky")
func cursorClipCommits() {
    var session = DrawingSession(shape: .line, anchor: Point(x: 0, y: 0))
    session.move(to: Point(x: 100, y: 50))
    session.setCursorClip(dx: -3, dy: 2)
    session.commitCursorClip()

    #expect(session.cursor == Point(x: 97, y: 52))

    // The next move is measured from the cursor the mouse reports, not from the one
    // the clip left behind, or every clip would add itself on top of the last.
    session.move(to: Point(x: 200, y: 50))
    #expect(session.line(constrained: false).end == Point(x: 200, y: 50))
}

@Test("a move and a cursor clip stack on the end they share")
func cursorClipStacksWithTheMove() {
    var session = DrawingSession(shape: .line, anchor: Point(x: 0, y: 0))
    session.move(to: Point(x: 100, y: 0))
    session.setSnapOffset(dx: 10, dy: 0)
    session.setCursorClip(dx: 4, dy: 0)

    let line = session.line(constrained: false)
    // The move carries both ends, the clip only the far one, so the line gets longer.
    #expect(line.start == Point(x: 10, y: 0))
    #expect(line.end == Point(x: 114, y: 0))
}
