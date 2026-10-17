import Testing
import Foundation
@testable import TesteMetaWord

struct PhysicsTests {
    let center = CGPoint(x: 700, y: 500)
    let bounds = CGRect(x: 16, y: 16, width: 1368, height: 968)

    func gap(_ bodies: [UUID: Physics.Body], _ sizes: [UUID: CGSize], _ a: UUID, _ b: UUID) -> CGFloat {
        Physics.signedDistance(Physics.rect(bodies[a]!.position, sizes[a]!), Physics.rect(bodies[b]!.position, sizes[b]!))
    }

    func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// A composition of `layout` widths and zones around a focus, budded from one point (as a
    /// fusion or a split does), laid out once and settled.
    func settle(focusSize: CGSize, _ layout: [(width: CGFloat, zone: Int)], from origin: CGPoint? = nil,
                affinity: @escaping (UUID, UUID) -> Bool = { _, _ in false })
        -> (bodies: [UUID: Physics.Body], sizes: [UUID: CGSize], zones: [UUID: Int], focus: UUID, cells: [UUID: CGPoint]) {
        let focus = UUID()
        var sizes = [focus: focusSize]
        var zones: [UUID: Int] = [:]
        for (width, zone) in layout {
            let id = UUID()
            sizes[id] = CGSize(width: width, height: 56)
            zones[id] = zone
        }
        var bodies = Physics.spawn([focus] + Array(zones.keys), core: focus, at: origin ?? CGPoint(x: 460, y: 470), seed: focus)
        let cells = Physics.layout(sizes: sizes, focus: focus, zones: zones, center: center,
                                   current: bodies.mapValues(\.position), affinity: affinity)
        for _ in 0..<600 { Physics.step(&bodies, sizes: sizes, targets: cells, bounds: bounds, dt: 1.0 / 60) }
        return (bodies, sizes, zones, focus, cells)
    }

    func expectNoBridges(_ bodies: [UUID: Physics.Body], _ sizes: [UUID: CGSize]) {
        let ids = Array(sizes.keys)
        for (i, a) in ids.enumerated() {
            for b in ids[(i + 1)...] { #expect(gap(bodies, sizes, a, b) > Physics.glassSpacing, "no glass bridge at rest") }
        }
    }

    @Test func theHoneycombCentersTheFocusAndOrdersTheZones() {
        let r = settle(focusSize: CGSize(width: 140, height: 58),
                       [(88, 1), (100, 1), (106, 1), (110, 2), (104, 2), (120, 3), (96, 3)])
        #expect(distance(r.bodies[r.focus]!.position, center) < 2, "the focus moves to the canvas center")
        for (id, cell) in r.cells { #expect(distance(r.bodies[id]!.position, cell) < 2, "every word reaches its cell") }
        func mean(_ zone: Int) -> CGFloat {
            let ids = r.zones.keys.filter { r.zones[$0] == zone }
            return ids.map { distance(r.cells[$0]!, center) }.reduce(0, +) / CGFloat(ids.count)
        }
        #expect(mean(1) < mean(2) && mean(2) < mean(3), "inner zones sit nearer the focus")
        expectNoBridges(r.bodies, r.sizes)
    }

    /// The pattern depends on the words, not on where they came from: the same composition
    /// budded from different points settles into the same cells.
    @Test func everyChangeSettlesIntoTheSamePattern() {
        let words: [(CGFloat, Int)] = [(120, 1), (96, 1), (130, 2), (110, 2), (100, 3)]
        let a = settle(focusSize: CGSize(width: 180, height: 60), words, from: CGPoint(x: 300, y: 300))
        let b = settle(focusSize: CGSize(width: 180, height: 60), words, from: CGPoint(x: 1100, y: 800))
        let shape = { (cells: [UUID: CGPoint]) in Set(cells.values.map { "\(Int(abs($0.y - 500).rounded())) \(Int(abs($0.x - 700).rounded()))" }) }
        #expect(shape(a.cells) == shape(b.cells), "the same honeycomb, at most mirrored")
    }

    @Test func outerZonesCloseInWhenInnerOnesAreEmpty() {
        #expect(Physics.zoneGap(3, occupied: [3]) == Physics.zoneGap(1), "a lone outer zone takes the inner ring")
        #expect(Physics.zoneGap(3, occupied: [1, 3]) == Physics.zoneGap(2))
        #expect(Physics.zoneGap(2, occupied: [2, 3]) == Physics.zoneGap(1))
        let r = settle(focusSize: CGSize(width: 140, height: 58), [(96, 3)])
        let outer = r.zones.keys.first!
        #expect(gap(r.bodies, r.sizes, outer, r.focus) < Physics.restGap + 4, "it sits beside the focus")
    }

    /// Eight words in the inner zone around a short focus, as after shaking querer.
    @Test func aCrowdedZoneStaysCompactAndDenseWordsStayCentral() {
        let widths: [CGFloat] = [100, 124, 132, 132, 206, 90, 140, 134]
        let r = settle(focusSize: CGSize(width: 140, height: 58), widths.map { ($0, 1) })
        expectNoBridges(r.bodies, r.sizes)
        let densest = r.zones.keys.max { r.sizes[$0]!.width < r.sizes[$1]!.width }!
        #expect(gap(r.bodies, r.sizes, densest, r.focus) < Physics.restGap + 4, "the densest word sits against the focus")
    }

    /// A long phrase as the focus with three zones around it, as in a long composition.
    @Test func aWideFocusKeepsItsZonesApart() {
        let r = settle(focusSize: CGSize(width: 560, height: 62),
                       [(140, 1), (120, 1), (130, 1), (126, 1), (90, 1), (118, 1), (130, 1), (124, 1),
                        (104, 2), (100, 2), (126, 3), (132, 3)])
        expectNoBridges(r.bodies, r.sizes)
    }

    /// Words that make a full phrase together attract: they end up next to each other.
    @Test func complementaryWordsAttractLikeOppositeCharges() {
        let focus = UUID(), a = UUID(), b = UUID()
        var sizes = [focus: CGSize(width: 140, height: 58)]
        var zones: [UUID: Int] = [:]
        for id in [a, b] { sizes[id] = CGSize(width: 100, height: 56); zones[id] = 3 }
        for _ in 0..<8 { let id = UUID(); sizes[id] = CGSize(width: 110, height: 56); zones[id] = 2 }
        let pair: Set<UUID> = [a, b]
        let cells = Physics.layout(sizes: sizes, focus: focus, zones: zones, center: center,
                                   affinity: { pair == [$0, $1] })
        let apart = Physics.layout(sizes: sizes, focus: focus, zones: zones, center: center)
        #expect(distance(cells[a]!, cells[b]!) < distance(apart[a]!, apart[b]!) || distance(cells[a]!, cells[b]!) < 160)
        #expect(distance(cells[a]!, cells[b]!) < 160, "the pair sits side by side")
    }

    /// A word let go away from home sets off gently and speeds up, instead of snapping back.
    @Test func aReleasedWordEasesIntoItsReturn() {
        let focus = UUID()
        let sizes = [focus: CGSize(width: 140, height: 58)]
        func speeds(ramp: CGFloat) -> [CGFloat] {
            var bodies = [focus: Physics.Body(position: CGPoint(x: 1200, y: 900), ramp: ramp)]
            return (0..<30).map { _ in
                Physics.step(&bodies, sizes: sizes, targets: [focus: center], bounds: bounds, dt: 1.0 / 60)
                return hypot(bodies[focus]!.velocity.dx, bodies[focus]!.velocity.dy)
            }
        }
        let eased = speeds(ramp: 0), snapped = speeds(ramp: 1)
        #expect(eased[2] < snapped[2] / 4, "a gentle start")
        #expect(eased[20] > eased[5], "then it speeds up")
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

    /// A fusion inside a large honeycomb (as in a long session) only reshapes its neighbourhood:
    /// the result takes its origins' place, the suggestions bud into free spots nearby, row
    /// neighbours make way, and every word far from it keeps its cell.
    @Test func aFusionOnlyReshapesItsNeighbourhood() {
        let focus = UUID()
        var sizes = [focus: CGSize(width: 140, height: 58)]
        var zones: [UUID: Int] = [:]
        for k in 0..<44 {
            let id = UUID()
            sizes[id] = CGSize(width: [96, 120, 140, 110, 160][k % 5], height: 56)
            zones[id] = 1 + k % 3
        }
        let grid = Physics.Grid(origin: center, sizes: sizes)
        let before = Physics.layout(sizes: sizes, focus: focus, zones: zones, center: center)
        // Two neighbours in one row fuse.
        let row = before.filter { $0.key != focus && abs($0.value.y - (center.y + grid.rowHeight)) < 1 }.sorted { $0.value.x < $1.value.x }
        let (a, b) = (row[0].key, row[1].key)
        let birth = CGPoint(x: (before[a]!.x + before[b]!.x) / 2, y: before[a]!.y)
        var cells = before
        cells[a] = nil; cells[b] = nil
        sizes[a] = nil; sizes[b] = nil
        let result = UUID(), suggestions = [UUID(), UUID()]
        sizes[result] = CGSize(width: 260, height: 56)
        for id in suggestions { sizes[id] = CGSize(width: 100, height: 56) }
        let births = Dictionary(uniqueKeysWithValues: ([result] + suggestions).map { ($0, birth) })
        let adapted = Physics.adapt(cells: cells, births: births, sizes: sizes, grid: grid, bounds: bounds)
        let after = Physics.compact(cells: adapted, sizes: sizes, grid: grid, toward: grid.origin, fixed: result, bounds: bounds)

        for (id, old) in cells where distance(old, birth) > 420 {
            #expect(after[id] == old, "a word far from the fusion keeps its cell")
        }
        let moved = cells.keys.filter { after[$0] != cells[$0] }
        #expect(moved.count <= 8, "only a few neighbours make way, not \(moved.count)")
        #expect(abs(after[result]!.y - birth.y) <= grid.rowHeight, "the result takes its origins' place")
        for id in suggestions { #expect(distance(after[id]!, birth) < 400, "suggestions bud nearby") }
        let ids = Array(after.keys)
        for (i, p) in ids.enumerated() {
            for q in ids[(i + 1)...] {
                let g = Physics.signedDistance(Physics.rect(after[p]!, sizes[p]!), Physics.rect(after[q]!, sizes[q]!))
                #expect(g > Physics.glassSpacing, "cells never overlap")
            }
        }
    }

    /// A full honeycomb has no holes: gravity moves nothing.
    @Test func gravityLeavesAFullHoneycombAlone() {
        let focus = UUID()
        var sizes = [focus: CGSize(width: 140, height: 58)]
        var zones: [UUID: Int] = [:]
        for k in 0..<30 {
            let id = UUID()
            sizes[id] = CGSize(width: [96, 120, 140, 110, 160][k % 5], height: 56)
            zones[id] = 1 + k % 3
        }
        let grid = Physics.Grid(origin: center, sizes: sizes)
        let cells = Physics.layout(sizes: sizes, focus: focus, zones: zones, center: center)
        #expect(Physics.compact(cells: cells, sizes: sizes, grid: grid, toward: center, fixed: focus, bounds: bounds) == cells)
    }

    /// Words gone from one side leave holes, and words budded far away hang loose: gravity
    /// settles them toward the focus without overlaps, and the structure gets compact again.
    @Test func gravityFillsHolesTowardTheFocus() {
        let focus = UUID()
        var sizes = [focus: CGSize(width: 220, height: 58)]
        var zones: [UUID: Int] = [:]
        for k in 0..<24 {
            let id = UUID()
            sizes[id] = CGSize(width: [96, 120, 140, 110][k % 4], height: 56)
            zones[id] = 1 + k % 3
        }
        let grid = Physics.Grid(origin: center, sizes: sizes)
        var cells = Physics.layout(sizes: sizes, focus: focus, zones: zones, center: center)
        // Everything left of the focus goes away; four words hang far to the right.
        for (id, p) in cells where id != focus && p.x < center.x - 60 { cells[id] = nil; sizes[id] = nil }
        for k in 0..<4 {
            let id = UUID()
            sizes[id] = CGSize(width: 110, height: 56)
            cells[id] = CGPoint(x: center.x + 560, y: grid.y(k - 2))
        }
        func spread(_ cells: [UUID: CGPoint]) -> CGFloat { cells.values.map { distance($0, center) }.max()! }
        let settled = Physics.compact(cells: cells, sizes: sizes, grid: grid, toward: center, fixed: focus, bounds: bounds)
        #expect(spread(settled) < spread(cells) - 150, "the loose words come closer")
        #expect(settled[focus] == center, "the focus stays")
        let ids = Array(settled.keys)
        for (i, p) in ids.enumerated() {
            for q in ids[(i + 1)...] {
                let g = Physics.signedDistance(Physics.rect(settled[p]!, sizes[p]!), Physics.rect(settled[q]!, sizes[q]!))
                #expect(g > Physics.glassSpacing, "cells never overlap")
            }
        }
    }

    /// The BubbleKey goes back to the center with the whole honeycomb, as one block.
    @Test func recenteringSlidesTheHoneycombAsOneBlock() {
        let key = UUID(), a = UUID(), b = UUID()
        let cells = [key: CGPoint(x: 900, y: 588), a: CGPoint(x: 760, y: 588), b: CGPoint(x: 830, y: 676)]
        let grid = Physics.Grid(origin: center, sizes: [key: CGSize(width: 140, height: 58)])
        let moved = Physics.recenter(cells: cells, grid: grid, focus: key, center: center)
        #expect(moved.cells[key] == center)
        for (p, q) in [(key, a), (key, b), (a, b)] {
            #expect(abs(distance(moved.cells[p]!, moved.cells[q]!) - distance(cells[p]!, cells[q]!)) < 0.001, "no word changes neighbours")
        }
        #expect(moved.grid.row(moved.cells[b]!.y) - moved.grid.row(moved.cells[key]!.y) == grid.row(cells[b]!.y) - grid.row(cells[key]!.y), "nor rows")
    }
}
