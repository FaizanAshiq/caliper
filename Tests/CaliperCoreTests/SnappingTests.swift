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
