import Testing
@testable import CaliperCore

@Test("backing pixels convert to points at 2x")
func backingToPointsRetina() {
    let scale = Scale(factor: 2.0)
    #expect(scale.points(fromBacking: 32) == 16.0)
    #expect(scale.points(fromBacking: 33) == 16.5)
}

@Test("backing pixels convert to points at 1x")
func backingToPointsNonRetina() {
    let scale = Scale(factor: 1.0)
    #expect(scale.points(fromBacking: 32) == 32.0)
}

@Test("points convert back to backing pixels")
func pointsToBacking() {
    #expect(Scale.retina.backing(fromPoints: 16.5) == 33.0)
}

@Test("values round to the nearest half point")
func halfPointRounding() {
    #expect(Scale.roundedToHalfPoint(16.24) == 16.0)
    #expect(Scale.roundedToHalfPoint(16.26) == 16.5)
    #expect(Scale.roundedToHalfPoint(16.75) == 17.0)
    #expect(Scale.roundedToHalfPoint(-16.26) == -16.5)
}
