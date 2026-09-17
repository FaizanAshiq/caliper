import Testing
@testable import CaliperCore

/// Builds a white field containing solid dark rectangles.
private func field(width: Int, height: Int, rects: [PixelRect]) -> ArrayPixelBuffer {
    var values = [Double](repeating: 1.0, count: width * height)
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


