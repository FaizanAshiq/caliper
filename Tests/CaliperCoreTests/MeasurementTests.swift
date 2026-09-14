import Testing
@testable import CaliperCore

@Test("line reports its component distances")
func lineComponents() {
    let line = LineMeasurement(start: Point(x: 10, y: 20), end: Point(x: 40, y: 60))
    #expect(line.dx == 30)
    #expect(line.dy == 40)
    #expect(line.distance == 50)
}

@Test("angle is measured counter clockwise with y growing downward")
func lineAngle() {
    let right = LineMeasurement(start: Point(x: 0, y: 0), end: Point(x: 10, y: 0))
    #expect(right.angleDegrees == 0)

    let up = LineMeasurement(start: Point(x: 0, y: 0), end: Point(x: 0, y: -10))
    #expect(up.angleDegrees == 90)

    let diagonal = LineMeasurement(start: Point(x: 0, y: 0), end: Point(x: 10, y: -10))
    #expect(diagonal.angleDegrees == 45)
}

@Test("shift constrains a line to the nearest 45 degrees")
func constrainToAxes() {
    let nearlyFlat = LineMeasurement(start: Point(x: 0, y: 0), end: Point(x: 100, y: 8))
    let flat = nearlyFlat.constrainedToAxes()
    #expect(flat.end.y == 0)
    #expect(flat.end.x == 100)

    let nearlyDiagonal = LineMeasurement(start: Point(x: 0, y: 0), end: Point(x: 100, y: -92))
    let diagonal = nearlyDiagonal.constrainedToAxes()
    #expect(Scale.roundedToHalfPoint(diagonal.dx) == Scale.roundedToHalfPoint(-diagonal.dy))
}

@Test("a box is built from two corners regardless of drag direction")
func boxFromCorners() {
    let dragged = BoxMeasurement.from(anchor: Point(x: 100, y: 100),
                                      cursor: Point(x: 40, y: 60),
                                      fromCentre: false)
    #expect(dragged.origin == Point(x: 40, y: 60))
    #expect(dragged.size == Size(width: 60, height: 40))
}

@Test("option draws a box outward from its centre")
func boxFromCentre() {
    let centred = BoxMeasurement.from(anchor: Point(x: 100, y: 100),
                                      cursor: Point(x: 130, y: 120),
                                      fromCentre: true)
    #expect(centred.origin == Point(x: 70, y: 80))
    #expect(centred.size == Size(width: 60, height: 40))
}
