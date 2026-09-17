import Testing
@testable import CaliperCore

@Test("a hairline rule does not clear the floor")
func hairlineRejected() {
    // The two widths a rule comes in, and the reading that put a label on the line
    // between two table rows.
    #expect(!(0.5 > GapCredibility.hairline))
    #expect(!(1 > GapCredibility.hairline))
}

@Test("the tightest deliberate spacing does clear it")
func ordinarySpacing() {
    #expect(1.5 > GapCredibility.hairline)
    #expect(24 > GapCredibility.hairline)
}
