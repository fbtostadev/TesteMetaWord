import Testing
import Foundation
@testable import TesteMetaWord

struct PhysicsTests {
    let center = CGPoint(x: 500, y: 500)
    let bounds = CGRect(x: 16, y: 16, width: 968, height: 968)

    func gap(_ bodies: [UUID: Physics.Body], _ sizes: [UUID: CGSize], _ a: UUID, _ b: UUID) -> CGFloat {
        Physics.signedDistance(Physics.rect(bodies[a]!.position, sizes[a]!), Physics.rect(bodies[b]!.position, sizes[b]!))
    }

    @Test func focusCentersAndEachZoneSettlesOnItsOwnRingWithoutGlassBridges() {
        let focus = UUID()
        var sizes = [focus: CGSize(width: 120, height: 58)]
        var zones: [UUID: Int] = [:]
        for (width, zone) in [(88, 1), (100, 1), (106, 1), (110, 2), (104, 2), (120, 3), (96, 3)] as [(CGFloat, Int)] {
            let id = UUID()
            sizes[id] = CGSize(width: width, height: 56)
            zones[id] = zone
        }
        // Born off-center, as a fusion result is.
        var bodies = Physics.spawn([focus] + Array(zones.keys), core: focus, at: CGPoint(x: 320, y: 380), seed: focus)
        for _ in 0..<240 {
            Physics.step(&bodies, sizes: sizes, focus: focus, zones: zones, center: center, bounds: bounds, dt: 1.0 / 60)
        }
        #expect(hypot(bodies[focus]!.position.x - center.x, bodies[focus]!.position.y - center.y) < 4, "the optical center moves to the canvas center")
        for (id, zone) in zones {
            // On its ring, or a little beyond it where a word of an inner ring stands in the way.
            let g = gap(bodies, sizes, id, focus)
            #expect(g > Physics.zoneGap(zone) - 8 && g < Physics.zoneGap(zone) + Physics.zoneSpacing, "zone \(zone) sits on its ring")
        }
        let ids = Array(sizes.keys)
        for a in ids {
            for b in ids where a != b { #expect(gap(bodies, sizes, a, b) > Physics.glassSpacing, "no glass bridge at rest") }
        }
    }

    @Test func outerZonesCloseInWhenInnerOnesAreEmpty() {
        #expect(Physics.zoneGap(3, occupied: [3]) == Physics.zoneGap(1), "a lone outer zone takes the inner ring")
        #expect(Physics.zoneGap(3, occupied: [1, 3]) == Physics.zoneGap(2))
        #expect(Physics.zoneGap(2, occupied: [2, 3]) == Physics.zoneGap(1))
        let focus = UUID(), outer = UUID()
        let sizes = [focus: CGSize(width: 120, height: 58), outer: CGSize(width: 96, height: 56)]
        var bodies = Physics.spawn([focus, outer], core: focus, at: center, seed: focus)
        for _ in 0..<240 {
            Physics.step(&bodies, sizes: sizes, focus: focus, zones: [outer: 3], center: center, bounds: bounds, dt: 1.0 / 60)
        }
        #expect(abs(gap(bodies, sizes, outer, focus) - Physics.zoneGap(1)) < 8, "it sits beside the focus")
    }

    @Test func zoneMembersSpreadEvenlyAroundTheFocus() {
        let focus = UUID(), members = [UUID(), UUID(), UUID()]
        var sizes = [focus: CGSize(width: 120, height: 58)]
        for id in members { sizes[id] = CGSize(width: 96, height: 56) }
        // All three start on the same side of the focus.
        let bodies = Dictionary(uniqueKeysWithValues: [(focus, Physics.Body(position: center))] + members.enumerated().map { k, id in
            (id, Physics.Body(position: CGPoint(x: center.x + 200, y: center.y - 40 + CGFloat(k) * 40)))
        })
        let targets = Physics.targets(bodies, sizes: sizes, focus: focus, zones: Dictionary(uniqueKeysWithValues: members.map { ($0, 1) }), center: center)
        let angles = members.map { atan2(targets[$0]!.y - center.y, targets[$0]!.x - center.x) }.sorted()
        let turns = [angles[1] - angles[0], angles[2] - angles[1], 2 * .pi + angles[0] - angles[2]]
        #expect(turns.allSatisfy { abs($0 - 2 * .pi / 3) < 0.35 }, "the spare room is shared: \(turns)")
        #expect(targets[focus] == center)
    }

    @Test func newWordsBudFromTheCoreOnDistinctImpulses() {
        let core = UUID(), first = UUID(), second = UUID()
        let born = Physics.spawn([core, first, second], core: core, at: center, seed: UUID())
        #expect(born[core] == Physics.Body(position: center))
        let v1 = born[first]!.velocity, v2 = born[second]!.velocity
        #expect(hypot(v1.dx, v1.dy) > 0 && hypot(v2.dx, v2.dy) > 0)
        let angle = acos((v1.dx * v2.dx + v1.dy * v2.dy) / (hypot(v1.dx, v1.dy) * hypot(v2.dx, v2.dy)))
        #expect(angle > 1, "siblings leave in clearly different directions")
        for id in [first, second] {
            #expect(hypot(born[id]!.position.x - center.x, born[id]!.position.y - center.y) < 2, "born inside the core")
        }
    }

    @Test func orbitSharesOnePeriodAndVanishesWithoutAmplitude() {
        let now = Physics.orbit(phase: 1, time: 10)
        let nextLap = Physics.orbit(phase: 1, time: 10 + Physics.orbitPeriod)
        #expect(abs(now.dx - nextLap.dx) < 0.001 && abs(now.dy - nextLap.dy) < 0.001)
        #expect(Physics.orbit(phase: 1 + Physics.familyLag, time: 10) != now)
        #expect(Physics.orbit(phase: 1, time: 10, amplitude: 0) == .zero)
    }

    /// Settles a composition and checks that no two words rest closer than the glass spacing.
    func settlesWithoutBridges(focusSize: CGSize, zones layout: [(width: CGFloat, zone: Int)], steps: Int = 900) -> (bodies: [UUID: Physics.Body], sizes: [UUID: CGSize], focus: UUID) {
        let focus = UUID()
        var sizes = [focus: focusSize]
        var zones: [UUID: Int] = [:]
        for (width, zone) in layout {
            let id = UUID()
            sizes[id] = CGSize(width: width, height: 56)
            zones[id] = zone
        }
        // Everything buds from one point, as a shake or a fusion does.
        var bodies = Physics.spawn([focus] + Array(zones.keys), core: focus, at: CGPoint(x: 460, y: 470), seed: focus)
        let wide = CGRect(x: 16, y: 16, width: 1368, height: 968)
        for _ in 0..<steps {
            Physics.step(&bodies, sizes: sizes, focus: focus, zones: zones, center: CGPoint(x: 700, y: 500), bounds: wide, dt: 1.0 / 60)
        }
        let ids = Array(sizes.keys)
        for (i, a) in ids.enumerated() {
            for b in ids[(i + 1)...] {
                #expect(gap(bodies, sizes, a, b) > Physics.glassSpacing, "no glass bridge at rest")
            }
        }
        return (bodies, sizes, focus)
    }

    /// Eight words in the inner zone around a short focus, as after shaking querer.
    @Test func aCrowdedZoneOverflowsInsteadOfPinningWords() {
        let widths: [CGFloat] = [100, 124, 132, 132, 206, 90, 140, 134]
        let result = settlesWithoutBridges(focusSize: CGSize(width: 140, height: 58), zones: widths.map { ($0, 1) })
        let gaps = result.sizes.keys.filter { $0 != result.focus }.map { gap(result.bodies, result.sizes, $0, result.focus) }
        #expect(gaps.contains { abs($0 - Physics.zoneGap(1)) < 8 }, "the ring is used")
        #expect(gaps.contains { $0 > Physics.zoneGap(1) + 40 }, "the words that do not fit move to the next ring")
    }

    /// A long phrase as the focus with three zones around it, as in a long composition.
    @Test func aWideFocusKeepsItsZonesApart() {
        let layout: [(CGFloat, Int)] = [(140, 1), (120, 1), (130, 1), (126, 1), (90, 1), (118, 1), (130, 1), (124, 1),
                                        (104, 2), (100, 2), (126, 3), (132, 3)]
        _ = settlesWithoutBridges(focusSize: CGSize(width: 560, height: 62), zones: layout)
    }
}
