import Testing
@testable import CaliperCore

/// Builds a white field containing solid dark rectangles.
private func field(width: Int, height: Int, rects: [PixelRect]) -> ArrayPixelBuffer {
    var values = [Double](repeating: 0.9725, count: width * height)
    for rect in rects {
        for y in rect.y ..< (rect.y + rect.height) {
            for x in rect.x ..< (rect.x + rect.width) {
                values[y * width + x] = 0.0
            }
        }
    }
    return ArrayPixelBuffer(width: width, height: height, luminances: values)
}

@Test("finds the first boundary in each direction")
func firstEdgeEachDirection() {
    let buffer = field(width: 100, height: 100,
                       rects: [PixelRect(x: 20, y: 30, width: 40, height: 20)])
    let detector = EdgeDetector(threshold: 0.12, runLength: 3)
    let inside = (x: 40, y: 40)

    #expect(detector.firstEdge(from: inside, direction: .left, in: buffer) == 20)
    #expect(detector.firstEdge(from: inside, direction: .right, in: buffer) == 59)
    #expect(detector.firstEdge(from: inside, direction: .up, in: buffer) == 30)
    #expect(detector.firstEdge(from: inside, direction: .down, in: buffer) == 49)
}

@Test("bounds enclose the element under the cursor")
func boundsAroundCursor() {
    let buffer = field(width: 100, height: 100,
                       rects: [PixelRect(x: 20, y: 30, width: 40, height: 20)])
    let detector = EdgeDetector(threshold: 0.12, runLength: 3)
    let bounds = detector.bounds(around: (x: 40, y: 40), in: buffer)
    #expect(bounds == PixelRect(x: 20, y: 30, width: 40, height: 20))
}


@Test("a soft shadow below the threshold is not treated as an edge")
func softShadowIgnored() {
    var values = [Double](repeating: 1.0, count: 100 * 100)
    for y in 0 ..< 100 {
        for x in 60 ..< 70 {
            values[y * 100 + x] = 0.95
        }
        for x in 20 ..< 40 {
            values[y * 100 + x] = 0.0
        }
    }
    let buffer = ArrayPixelBuffer(width: 100, height: 100, luminances: values)
    let detector = EdgeDetector(threshold: 0.12, runLength: 3)
    #expect(detector.firstEdge(from: (x: 50, y: 50), direction: .right, in: buffer) == nil)
    #expect(detector.firstEdge(from: (x: 50, y: 50), direction: .left, in: buffer) == 40)
}

@Test("a one pixel line still registers when runLength allows it")
func hairlineEdge() {
    var values = [Double](repeating: 1.0, count: 100 * 100)
    for y in 0 ..< 100 {
        values[y * 100 + 70] = 0.0
    }
    let buffer = ArrayPixelBuffer(width: 100, height: 100, luminances: values)
    let detector = EdgeDetector(threshold: 0.12, runLength: 1)
    #expect(detector.firstEdge(from: (x: 50, y: 50), direction: .right, in: buffer) == 69)
}

@Test("returns nil when the cursor sits on a flat field")
func flatFieldHasNoEdges() {
    let buffer = field(width: 50, height: 50, rects: [])
    let detector = EdgeDetector(threshold: 0.12, runLength: 3)
    #expect(detector.bounds(around: (x: 25, y: 25), in: buffer) == nil)
}

/// A table the way a browser draws one at 2x, every number measured off a real
/// screenshot rather than invented: rows of #F8F8F8 112 backing pixels tall, parted
/// by a one point rule that is two pixels of #DEDEE0, inside a dark card. The rule
/// is a luminance difference of 0.1013, and two pixels is all it ever gets.
private func tableRows() -> ArrayPixelBuffer {
    let width = 400, height = 700
    var values = [Double](repeating: 0.9725, count: width * height)
    for y in 0 ..< height {
        for x in 0 ..< width where x < 4 || x >= width - 4 { values[y * width + x] = 0.2 }
    }
    for y in 0 ..< height where y < 4 || y >= height - 4 {
        for x in 0 ..< width { values[y * width + x] = 0.2 }
    }
    for rule in 1 ... 5 {
        for y in (rule * 112) ..< (rule * 112 + 2) {
            for x in 4 ..< (width - 4) { values[y * width + x] = 0.8712 }
        }
    }
    return ArrayPixelBuffer(width: width, height: height, luminances: values)
}

@Test("a table row is found, not the whole table it sits in")
func tableRowBounds() {
    let buffer = tableRows()
    let bounds = EdgeDetector(threshold: 0.09, scale: .retina)
        .bounds(around: (x: 200, y: 280), in: buffer)
    #expect(bounds?.height == 110)
    #expect(bounds?.y == 226)
}

/// The bug this replaced: three pixels is a point and a half, so the rule between two
/// rows never held long enough to count and the walk ran on to the edge of the card.
@Test("a fixed three pixel run misses the row at every threshold")
func fixedRunMissesTheRow() {
    let buffer = tableRows()
    for step in 1 ... 90 {
        let bounds = EdgeDetector(threshold: Double(step) / 100, runLength: 3)
            .bounds(around: (x: 200, y: 280), in: buffer)
        #expect(bounds?.height != 110)
    }
}

@Test("the run is one point, in whatever pixels that display makes a point")
func runLengthFollowsTheScale() {
    #expect(EdgeDetector(threshold: 0.12, scale: .retina).runLength == 2)
    #expect(EdgeDetector(threshold: 0.12, scale: .nonRetina).runLength == 1)
}
