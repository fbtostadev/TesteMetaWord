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
            #expect(abs(gap(bodies, sizes, id, focus) - Physics.zoneGap(zone)) < 8, "zone \(zone) sits on its ring")
        }
        let ids = Array(sizes.keys)
        for a in ids {
            for b in ids where a != b { #expect(gap(bodies, sizes, a, b) > 32, "no glass bridge at rest") }
        }
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
        #expect(abs(angles[1] - angles[0] - 2 * .pi / 3) < 0.01)
        #expect(abs(angles[2] - angles[1] - 2 * .pi / 3) < 0.01)
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
}
