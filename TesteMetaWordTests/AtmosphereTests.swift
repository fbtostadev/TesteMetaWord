import Testing
import Foundation
@testable import TesteMetaWord

struct AtmosphereTests {
    @Test func emptyZonesStayDarkEvenWhenTheFocusIsEngaged() {
        let input = AtmosphereInput(focusID: UUID(), focus: CGRect(x: 400, y: 470, width: 310, height: 62),
                                    occupied: [3], focusEngaged: true, pair: nil)
        let frame = input.frame
        #expect(frame.zones.x == 0 && frame.zones.y == 0)
        #expect(frame.zones.z == 0.022)
        #expect(frame.pairIntensity == 0)
        #expect(frame.source == frame.focus && frame.target == frame.focus,
                "an inactive pair must never interpolate from the canvas origin")
        let absent = AtmosphereInput(focusID: nil, focus: .zero, occupied: [1, 2, 3], focusEngaged: true, pair: nil)
        #expect(absent.frame == .zero, "no field before focus geometry exists")
    }

    @Test func lightUsesVisibleSurfacesButIntentUsesLogicalDistance() {
        let pair = AtmosphereInput.Pair(
            id: MergePair(source: UUID(), target: UUID()),
            source: CGRect(x: 300, y: 300, width: 90, height: 56),
            target: CGRect(x: 450, y: 300, width: 120, height: 56),
            logicalGap: -25.2, distance: 24, armed: true, resistance: 1)
        let input = AtmosphereInput(focusID: UUID(), focus: pair.target,
                                    occupied: [1], focusEngaged: false, pair: pair)
        let frame = input.frame
        #expect(frame.source.x == pair.source.midX && frame.target.x == pair.target.midX)
        #expect(abs(frame.proximity - 1) < 0.00001, "membrane recoil must not redefine gesture intent")
        #expect(abs(frame.pairIntensity - 0.13 * 0.45) < 0.00001)
        #expect(frame.zones.x == 0.06, "an unrelated active pair must not boost the focus zone")
        #expect(frame.magnitudeSquared.isFinite)
    }
}
