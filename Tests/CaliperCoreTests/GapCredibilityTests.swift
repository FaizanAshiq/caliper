import Testing
@testable import CaliperCore

// A 1920 by 1080 screen, so the ceiling is 768 across and 432 down.
private let across: Double = 1920
private let down: Double = 1080

@Test("ordinary spacing between two cards is credible")
func ordinarySpacing() {
    #expect(GapCredibility.isSpacing(24, screenSpan: across))
    #expect(GapCredibility.isSpacing(90, screenSpan: across))
    #expect(GapCredibility.isSpacing(150.5, screenSpan: down))
}

@Test("a hairline rule is not spacing")
func hairlineRejected() {
    // The reading that put a label on a table row border.
    #expect(!GapCredibility.isSpacing(1, screenSpan: down))
    #expect(!GapCredibility.isSpacing(0.5, screenSpan: down))
    #expect(GapCredibility.isSpacing(1.5, screenSpan: down))
}

@Test("a gap running half the screen is the page, not spacing")
func pageRejected() {
    // The reading that ran from a card's bottom edge past a low contrast card below it
    // and on down the screen.
    #expect(!GapCredibility.isSpacing(502.5, screenSpan: down))
    #expect(!GapCredibility.isSpacing(900, screenSpan: across))
}

@Test("the ceiling sits exactly on four tenths of the axis")
func ceilingIsInclusive() {
    #expect(GapCredibility.isSpacing(432, screenSpan: down))
    #expect(!GapCredibility.isSpacing(432.5, screenSpan: down))
    #expect(GapCredibility.isSpacing(768, screenSpan: across))
    #expect(!GapCredibility.isSpacing(768.5, screenSpan: across))
}


@Test("before the first layout only the hairline floor applies")
func noScreenYetForGaps() {
    #expect(GapCredibility.isSpacing(5000, screenSpan: 0))
    #expect(!GapCredibility.isSpacing(1, screenSpan: 0))
}
