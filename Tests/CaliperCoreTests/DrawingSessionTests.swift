import Testing
@testable import CaliperCore

@Test("dragging moves only the cursor end")
func plainDrag() {
    var session = DrawingSession(shape: .line, anchor: Point(x: 10, y: 10))
    session.move(to: Point(x: 50, y: 40))
    #expect(session.anchor == Point(x: 10, y: 10))
    #expect(session.cursor == Point(x: 50, y: 40))
}

@Test("holding space translates the whole shape without resizing it")
func spaceMovesShape() {
    var session = DrawingSession(shape: .line, anchor: Point(x: 10, y: 10))
    session.move(to: Point(x: 50, y: 40))
    let lengthBefore = session.line(constrained: false).distance

    session.beginMoving(from: Point(x: 50, y: 40))
    session.move(to: Point(x: 70, y: 40))
    session.endMoving()

    #expect(session.anchor == Point(x: 30, y: 10))
    #expect(session.cursor == Point(x: 70, y: 40))
    #expect(session.line(constrained: false).distance == lengthBefore)
}

@Test("releasing space resumes resizing rather than moving")
func releasingSpaceResumesDrag() {
    var session = DrawingSession(shape: .line, anchor: Point(x: 0, y: 0))
    session.move(to: Point(x: 10, y: 0))
    session.beginMoving(from: Point(x: 10, y: 0))
    session.move(to: Point(x: 20, y: 0))
    session.endMoving()
    session.move(to: Point(x: 40, y: 0))

    #expect(session.anchor == Point(x: 10, y: 0))
    #expect(session.cursor == Point(x: 40, y: 0))
}

@Test("arrow keys nudge the cursor end only")
func nudge() {
    var session = DrawingSession(shape: .line, anchor: Point(x: 0, y: 0))
    session.move(to: Point(x: 20, y: 0))
    session.nudge(dx: 1, dy: 0)
    #expect(session.cursor == Point(x: 21, y: 0))
    session.nudge(dx: 10, dy: 0)
    #expect(session.cursor == Point(x: 31, y: 0))
    #expect(session.anchor == Point(x: 0, y: 0))
}

@Test("constrain squares a box and snaps a line")
func constrain() {
    var box = DrawingSession(shape: .box, anchor: Point(x: 0, y: 0))
    box.move(to: Point(x: 100, y: 40))
    let squared = box.box(constrained: true, fromCentre: false)
    #expect(squared.size == Size(width: 100, height: 100))

    var line = DrawingSession(shape: .line, anchor: Point(x: 0, y: 0))
    line.move(to: Point(x: 100, y: 8))
    #expect(line.line(constrained: true).end.y == 0)
}

@Test("shift and option together square the box around its centre")
func squareFromCentre() {
    var box = DrawingSession(shape: .box, anchor: Point(x: 100, y: 100))
    box.move(to: Point(x: 150, y: 120))

    let squared = box.box(constrained: true, fromCentre: true)

    // The longer half is 50, so the square is 100 a side and still centred on where
    // the mouse went down rather than hanging off one of its corners.
    #expect(squared.size == Size(width: 100, height: 100))
    #expect(squared.origin == Point(x: 50, y: 50))
}

@Test("shift alone still squares from the corner the drag started at")
func squareFromCorner() {
    var box = DrawingSession(shape: .box, anchor: Point(x: 100, y: 100))
    box.move(to: Point(x: 150, y: 120))

    let squared = box.box(constrained: true, fromCentre: false)

    #expect(squared.size == Size(width: 50, height: 50))
    #expect(squared.origin == Point(x: 100, y: 100))
}
