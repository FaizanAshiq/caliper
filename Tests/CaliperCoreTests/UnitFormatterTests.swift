import Testing
@testable import CaliperCore

@Test("whole points drop the decimal, halves keep it")
func pointFormatting() {
    let formatter = UnitFormatter(scale: .retina, showBackingPixels: false)
    #expect(formatter.display(points: 16.0) == "16 pt")
    #expect(formatter.display(points: 16.5) == "16.5 pt")
}

@Test("backing pixels appear as a secondary reading when enabled")
func secondaryUnit() {
    let formatter = UnitFormatter(scale: .retina, showBackingPixels: true)
    #expect(formatter.display(points: 16.5) == "16.5 pt · 33 px")
}

@Test("a box reads as width by height")
func boxDisplay() {
    let formatter = UnitFormatter(scale: .retina, showBackingPixels: false)
    let box = BoxRect(origin: Point(x: 0, y: 0), size: Size(width: 220, height: 48))
    #expect(formatter.display(box: box) == "220 × 48 pt")
}

@Test("a line reads as distance with its components")
func lineDisplay() {
    let formatter = UnitFormatter(scale: .retina, showBackingPixels: false)
    let line = LineMeasurement(start: Point(x: 0, y: 0), end: Point(x: 30, y: 40))
    #expect(formatter.display(line: line) == "50 pt · dx 30 · dy 40")
}

@Test("css copy format emits pastable declarations")
func cssClipboard() {
    let formatter = UnitFormatter(scale: .retina, showBackingPixels: false)
    let box = BoxRect(origin: Point(x: 0, y: 0), size: Size(width: 220, height: 48))
    #expect(formatter.clipboard(box: box, format: .css) == "width: 220px; height: 48px;")
    #expect(formatter.clipboard(box: box, format: .value) == "220 × 48")
}

@Test("values are snapped to the half point grid before display")
func snapsBeforeDisplay() {
    let formatter = UnitFormatter(scale: .retina, showBackingPixels: false)
    #expect(formatter.display(points: 16.26) == "16.5 pt")
}

@Test("gaps copy with the side they were measured on")
func gapsCopyLabelled() {
    let formatter = UnitFormatter(scale: Scale(factor: 2), showBackingPixels: true)
    #expect(formatter.clipboard(gaps: [("left", 24), ("right", 40.4)]) == "left 24  right 40.5")
}

@Test("a compact value drops the units a gap label has no room for")
func compactDropsUnits() {
    let formatter = UnitFormatter(scale: Scale(factor: 2), showBackingPixels: true)
    #expect(formatter.compact(points: 16) == "16")
    #expect(formatter.compact(points: 16.4) == "16.5")
    // display keeps them, so the readout and the gap labels stay different on purpose.
    #expect(formatter.display(points: 16) == "16 pt · 32 px")
}
