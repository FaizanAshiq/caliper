import Testing
@testable import CaliperCore

private let screen = Size(width: 1920, height: 1080)

private func region(_ width: Double, _ height: Double) -> BoxRect {
    BoxRect(origin: Point(x: 0, y: 0), size: Size(width: width, height: height))
}

@Test("a card sized region is a thing")
func cardIsAThing() {
    #expect(RegionKind.of(region(320, 240), onScreen: screen) == .thing)
    #expect(RegionKind.of(region(44, 44), onScreen: screen) == .thing)
}

@Test("the gutter between two cards is a space")
func gutterIsASpace() {
    // The reading that started this: 99 points wide running 712.5 down a 1080 screen.
    // Narrow enough to look like nothing, tall enough to give itself away.
    #expect(RegionKind.of(region(99, 712.5), onScreen: screen) == .space)
}

@Test("a divider row between two rows of cards is a space on the other axis")
func wideShortGutterIsASpace() {
    #expect(RegionKind.of(region(1400, 24), onScreen: screen) == .space)
}

@Test("the page behind everything is a space")
func pageIsASpace() {
    #expect(RegionKind.of(region(1920, 1080), onScreen: screen) == .space)
}

@Test("the boundary is inclusive, so exactly four tenths counts as a space")
func boundaryIsInclusive() {
    #expect(RegionKind.of(region(100, 432), onScreen: screen) == .space)
    #expect(RegionKind.of(region(100, 431), onScreen: screen) == .thing)
}

@Test("before the first layout there is no screen to measure against")
func noScreenYet() {
    // Guessing space here would blank the reading on the very first hover.
    #expect(RegionKind.of(region(99, 712.5), onScreen: Size(width: 0, height: 0)) == .thing)
}
