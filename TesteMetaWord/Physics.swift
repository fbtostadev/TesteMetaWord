import CoreGraphics
import Foundation

/// Pure 2D physics for the organic composition. Bodies are capsule centers in canvas points.
/// Each word is pulled to its cell in an organic honeycomb around the focus (see `layout`),
/// computed once per change; repulsion keeps cells from touching on the way. The view freezes the physics during a gesture and adds the idle orbit on top.
enum Physics {
    /// Surfaces closer than this merge into one glass shape (the GlassEffectContainer spacing).
    static let glassSpacing: CGFloat = 24
    /// Resting gap between surfaces. Larger than `glassSpacing`, so words never bridge at rest.
    static let restGap: CGFloat = 30
    static let stiffness: CGFloat = 150
    /// Each occupied zone sits one word layer (56 pt + rest gap) beyond the previous one.
    static let zoneSpacing: CGFloat = 86
    /// Spring toward each word's target (slot or canvas center), close to critically damped.
    static let pull: CGFloat = 120
    static let damping: CGFloat = 18
    static let friction: CGFloat = 40
    static let maxSpeed: CGFloat = 900
    static let spawnSpeed: CGFloat = 520
    static let orbitAmplitude: CGFloat = 4
    static let orbitPeriod: TimeInterval = 6
    /// Phase delay between a fusion result and each suggestion born from it.
    static let familyLag = 0.6

    struct Body: Equatable {
        var position: CGPoint
        var velocity = CGVector.zero
        /// 0 → 1 after a release: the pull home grows along an ease-in curve, so a word let go at
        /// the edge sets off gently, speeds up and settles, instead of snapping back.
        var ramp: CGFloat = 1
    }

    /// Time for the pull home to reach full strength after a release.
    static let rampDuration: CGFloat = 0.45

    /// Target surface distance from the focus for atmosphere zone 1 (inner), 2 or 3 (outer).
    /// Empty zones take no ring: an outer zone closes in on the focus when the inner ones empty.
    static func zoneGap(_ zone: Int, occupied: Set<Int> = [1, 2, 3]) -> CGFloat {
        restGap + CGFloat(occupied.count { $0 < zone }) * zoneSpacing
    }

    static func rect(_ center: CGPoint, _ size: CGSize) -> CGRect {
        CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }

    /// Capsule distance uses center-line segments, avoiding false corner proximity.
    /// Negative values measure penetration into the two capsule surfaces.
    static func signedDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let ar = a.height / 2, br = b.height / 2
        let horizontal = max(0, max(a.minX + ar, b.minX + br) - min(a.maxX - ar, b.maxX - br))
        return hypot(horizontal, a.midY - b.midY) - ar - br
    }

    /// The chip whose capsule contains `point`; where capsules overlap, the nearest center wins.
    static func hit(_ point: CGPoint, centers: [UUID: CGPoint], sizes: [UUID: CGSize]) -> UUID? {
        centers.compactMap { id, center -> (id: UUID, distance: CGFloat)? in
            guard let size = sizes[id] else { return nil }
            let radius = size.height / 2
            let along = max(0, abs(point.x - center.x) - max(0, size.width / 2 - radius))
            guard hypot(along, point.y - center.y) <= radius else { return nil }
            return (id, hypot(point.x - center.x, point.y - center.y))
        }.min { $0.distance < $1.distance }?.id
    }

    /// Advances every body by `dt` toward its place in `targets` (see `layout`).
    static func step(_ bodies: inout [UUID: Body], sizes: [UUID: CGSize], targets: [UUID: CGPoint], bounds: CGRect, dt: CGFloat) {
        let ids = Array(bodies.keys)
        var acceleration = Dictionary(uniqueKeysWithValues: ids.map { ($0, CGVector.zero) })
        for i in ids.indices {
            for j in ids.indices where j > i {
                let a = ids[i], b = ids[j]
                guard let sa = sizes[a], let sb = sizes[b] else { continue }
                let pa = bodies[a]!.position, pb = bodies[b]!.position
                let gap = signedDistance(rect(pa, sa), rect(pb, sb))
                guard gap < restGap else { continue }
                let force = unit(from: pb, to: pa) * (stiffness * (restGap - gap))
                acceleration[a]! += force
                acceleration[b]! -= force
            }
        }
        for (id, target) in targets where bodies[id] != nil {
            let p = bodies[id]!.position
            let r = bodies[id]!.ramp
            acceleration[id]! += CGVector(dx: target.x - p.x, dy: target.y - p.y) * (pull * r * r * (3 - 2 * r))
        }
        let decay = exp(-damping * dt)
        for (id, a) in acceleration {
            var body = bodies[id]!
            var v = CGVector(dx: (body.velocity.dx + a.dx * dt) * decay, dy: (body.velocity.dy + a.dy * dt) * decay)
            let speed = hypot(v.dx, v.dy)
            let limited = min(maxSpeed, max(0, speed - friction * dt))
            v = speed > 0 ? v * (limited / speed) : .zero
            body.position.x += v.dx * dt
            body.position.y += v.dy * dt
            if let size = sizes[id] {
                let clamped = clamp(body.position, size: size, in: bounds)
                if clamped.x != body.position.x { v.dx = 0 }
                if clamped.y != body.position.y { v.dy = 0 }
                body.position = clamped
            }
            body.velocity = v
            body.ramp = min(1, body.ramp + dt / rampDuration)
            bodies[id] = body
        }
    }

    /// The rows of the honeycomb: where row 0 lies and how far apart rows are. Fixed between full
    /// layouts, so local changes keep every other word in its row.
    struct Grid: Equatable {
        var origin: CGPoint
        var rowHeight: CGFloat

        init(origin: CGPoint, sizes: [UUID: CGSize]) {
            self.origin = origin
            rowHeight = (sizes.values.map(\.height).max() ?? 56) + restGap
        }

        func row(_ y: CGFloat) -> Int { Int(((y - origin.y) / rowHeight).rounded()) }
        func y(_ row: Int) -> CGFloat { origin.y + CGFloat(row) * rowHeight }
    }

    /// A local change of the honeycomb: every word in `cells` keeps its cell, except neighbours
    /// that make way; each new word (in `births`, where it was born) settles in the nearest spot
    /// that fits, either a free one or one opened by sliding its row neighbours outward just
    /// enough, whichever disturbs less. Words far from the change never move. Widest words first,
    /// so a fusion result takes the place of its origins before its suggestions bud around it.
    static func adapt(cells: [UUID: CGPoint], births: [UUID: CGPoint], sizes: [UUID: CGSize], grid: Grid,
                      bounds: CGRect, affinity: (UUID, UUID) -> Bool = { _, _ in false }) -> [UUID: CGPoint] {
        var cells = cells
        func spans(_ row: Int) -> [(id: UUID, lo: CGFloat, hi: CGFloat)] {
            cells.compactMap { id, p in
                guard grid.row(p.y) == row, let w = sizes[id]?.width else { return nil }
                return (id, p.x - w / 2, p.x + w / 2)
            }.sorted { $0.lo < $1.lo }
        }
        let newcomers = births.keys.filter { sizes[$0] != nil }.sorted {
            (-sizes[$0]!.width, $0.uuidString) < (-sizes[$1]!.width, $1.uuidString)
        }
        for id in newcomers {
            let want = births[id]!, half = sizes[id]!.width / 2
            let home = grid.row(want.y)
            var best: (cost: CGFloat, x: CGFloat, row: Int, moves: [UUID: CGFloat])?
            for row in (home - 3)...(home + 3) {
                let y = grid.y(row)
                guard y > bounds.minY, y < bounds.maxY else { continue }
                let taken = spans(row)
                let rise = abs(y - want.y)
                // A free spot: at the birth point or right beside a word of the row.
                var free = [want.x]
                for span in taken { free += [span.lo - restGap - half, span.hi + restGap + half] }
                for x in free where x - half >= bounds.minX && x + half <= bounds.maxX
                    && !taken.contains(where: { x - half < $0.hi + restGap - 0.5 && x + half > $0.lo - restGap + 0.5 }) {
                    var cost = hypot(x - want.x, rise)
                    let partners = cells.filter { other, p in
                        abs(p.y - y) < grid.rowHeight * 1.5 && abs(p.x - x) < half + (sizes[other]?.width ?? 0) / 2 + restGap * 2 && affinity(id, other)
                    }
                    cost -= 45 * CGFloat(partners.count)
                    if best == nil || cost < best!.cost { best = (cost, x, row, [:]) }
                }
                // A spot opened at the birth point: row neighbours slide outward just enough.
                var moves: [UUID: CGFloat] = [:], edge = want.x + half
                for span in taken where (span.lo + span.hi) / 2 >= want.x {
                    let shift = max(0, edge + restGap - span.lo)
                    if shift > 0 { moves[span.id] = shift }
                    edge = span.hi + shift
                }
                edge = want.x - half
                for span in taken.reversed() where (span.lo + span.hi) / 2 < want.x {
                    let shift = max(0, span.hi - (edge - restGap))
                    if shift > 0 { moves[span.id] = -shift }
                    edge = span.lo - shift
                }
                let inside = moves.allSatisfy { id, dx in
                    let p = cells[id]!, w = sizes[id]!.width / 2
                    return p.x + dx - w >= bounds.minX && p.x + dx + w <= bounds.maxX
                }
                if inside, want.x - half >= bounds.minX, want.x + half <= bounds.maxX {
                    let cost = rise + 0.6 * moves.values.reduce(0) { $0 + abs($1) }
                    if best == nil || cost < best!.cost { best = (cost, want.x, row, moves) }
                }
            }
            guard let best else { continue }
            for (other, dx) in best.moves { cells[other]!.x += dx }
            cells[id] = CGPoint(x: best.x, y: grid.y(best.row))
        }
        return cells
    }

    /// Gentle gravity toward `core` (the honeycomb's fixed center, not the moving focus, so a
    /// hole-free honeycomb stays still): holes left by words that went away (a fusion, a split,
    /// an Undo) are filled from the inside out. In order of distance to `core`, a word
    /// hops into a free spot of a nearby row that is clearly closer to `core` (by `minGain`,
    /// within `maxHop`), and the spot it leaves is there for the next one. Words with no hole
    /// nearby never move, so the structure stays compact without a global reshuffle.
    static let minGain: CGFloat = 30
    static let maxHop: CGFloat = 220

    static func compact(cells: [UUID: CGPoint], sizes: [UUID: CGSize], grid: Grid, toward core: CGPoint,
                        fixed: UUID?, bounds: CGRect) -> [UUID: CGPoint] {
        var cells = cells
        for _ in 0..<4 {
            var moved = false
            let order = cells.keys.filter { $0 != fixed && sizes[$0] != nil }.sorted {
                (hypot(cells[$0]!.x - core.x, cells[$0]!.y - core.y), $0.uuidString) < (hypot(cells[$1]!.x - core.x, cells[$1]!.y - core.y), $1.uuidString)
            }
            for id in order {
                let here = cells[id]!, half = sizes[id]!.width / 2
                let reach = hypot(here.x - core.x, here.y - core.y)
                let home = grid.row(here.y)
                var best: (distance: CGFloat, point: CGPoint)?
                for row in (home - 2)...(home + 2) {
                    let y = grid.y(row)
                    let taken = cells.compactMap { other, p -> (lo: CGFloat, hi: CGFloat)? in
                        guard other != id, grid.row(p.y) == row, let w = sizes[other]?.width else { return nil }
                        return (p.x - w / 2, p.x + w / 2)
                    }
                    var spots = abs(row - grid.row(core.y)) % 2 == 0 ? [core.x] : [core.x - half - restGap / 2, core.x + half + restGap / 2]
                    for span in taken { spots += [span.lo - restGap - half, span.hi + restGap + half] }
                    for x in spots where x - half >= bounds.minX && x + half <= bounds.maxX
                        && !taken.contains(where: { x - half < $0.hi + restGap - 0.5 && x + half > $0.lo - restGap + 0.5 }) {
                        let p = CGPoint(x: x, y: y)
                        let d = hypot(x - core.x, y - core.y)
                        guard d < reach - minGain, hypot(x - here.x, y - here.y) <= maxHop else { continue }
                        if best == nil || d < best!.distance { best = (d, p) }
                    }
                }
                if let best {
                    cells[id] = best.point
                    moved = true
                }
            }
            if !moved { break }
        }
        return cells
    }

    /// Centers the BubbleKey by sliding the whole honeycomb as one block: every cell and the rows
    /// move by the same offset, so no word changes neighbours or row.
    static func recenter(cells: [UUID: CGPoint], grid: Grid, focus: UUID?, center: CGPoint) -> (cells: [UUID: CGPoint], grid: Grid) {
        guard let focus, let key = cells[focus] else { return (cells, grid) }
        let dx = center.x - key.x, dy = center.y - key.y
        var grid = grid
        grid.origin = CGPoint(x: grid.origin.x + dx, y: grid.origin.y + dy)
        return (cells.mapValues { CGPoint(x: $0.x + dx, y: $0.y + dy) }, grid)
    }

    /// Organic honeycomb around the focus, for a whole composition: at launch and when the canvas
    /// changes size. Later changes are local (see `adapt`). The same words always give the same
    /// pattern; only its density varies.
    ///
    /// The focus sits at `center`. Words lie in rows of capsules, `restGap` apart; odd rows split
    /// at the center like offset brick courses, so neighbours nest as in a honeycomb. Zone by zone
    /// (inner first) and widest first, each word takes the free spot nearest the center, leaning
    /// toward a placed word it would make a full phrase with (`affinity`): complementary words
    /// attract like opposite charges. The pattern never depends on where words are; of its four
    /// mirror images, the one that moves the words least from `current` is used.
    static func layout(sizes: [UUID: CGSize], focus: UUID?, zones: [UUID: Int], center: CGPoint,
                       current: [UUID: CGPoint] = [:], affinity: (UUID, UUID) -> Bool = { _, _ in false }) -> [UUID: CGPoint] {
        guard let focus, let focusSize = sizes[focus] else { return [:] }
        let rowHeight = Grid(origin: center, sizes: sizes).rowHeight
        var rows: [Int: [ClosedRange<CGFloat>]] = [0: [(center.x - focusSize.width / 2)...(center.x + focusSize.width / 2)]]
        var targets = [focus: center]
        let words = zones.keys.filter { $0 != focus && sizes[$0] != nil }.sorted {
            (zones[$0]!, -sizes[$0]!.width, $0.uuidString) < (zones[$1]!, -sizes[$1]!.width, $1.uuidString)
        }
        let reach = max(2, Int((Double(words.count) / 2).squareRoot().rounded(.up)) + 2)
        for id in words {
            let half = sizes[id]!.width / 2
            var best: (cost: CGFloat, row: Int, x: CGFloat)?
            for row in -reach...reach {
                let y = center.y + CGFloat(row) * rowHeight
                let taken = rows[row] ?? []
                var candidates = row % 2 == 0 ? [center.x] : [center.x - half - restGap / 2, center.x + half + restGap / 2]
                for span in taken { candidates += [span.lowerBound - restGap - half, span.upperBound + restGap + half] }
                for x in candidates where !taken.contains(where: { x - half < $0.upperBound + restGap - 0.5 && x + half > $0.lowerBound - restGap + 0.5 }) {
                    var cost = hypot(x - center.x, y - center.y)
                    let partners = targets.filter { other, p in
                        abs(p.y - y) < rowHeight * 1.5 && abs(p.x - x) < half + sizes[other]!.width / 2 + restGap * 2 && affinity(id, other)
                    }
                    cost -= 45 * CGFloat(partners.count)
                    if best == nil || cost < best!.cost { best = (cost, row, x) }
                }
            }
            guard let best else { continue }
            rows[best.row, default: []].append((best.x - half)...(best.x + half))
            targets[id] = CGPoint(x: best.x, y: center.y + CGFloat(best.row) * rowHeight)
        }
        let mirrors = [(1, 1), (-1, 1), (1, -1), (-1, -1)].map { sx, sy in
            targets.mapValues { CGPoint(x: center.x + CGFloat(sx) * ($0.x - center.x), y: center.y + CGFloat(sy) * ($0.y - center.y)) }
        }
        func travel(_ cells: [UUID: CGPoint]) -> CGFloat {
            cells.reduce(0) { sum, cell in sum + (current[cell.key].map { hypot($0.x - cell.value.x, $0.y - cell.value.y) } ?? 0) }
        }
        return mirrors.min { travel($0) < travel($1) }!
    }

    private static func unit(from a: CGPoint, to b: CGPoint) -> CGVector {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        return length < 0.001 ? CGVector(dx: 1, dy: 0) : CGVector(dx: dx / length, dy: dy / length)
    }

    static func clamp(_ point: CGPoint, size: CGSize, in bounds: CGRect) -> CGPoint {
        func axis(_ value: CGFloat, _ half: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            low + half > high - half ? (low + high) / 2 : min(high - half, max(low + half, value))
        }
        return CGPoint(x: axis(point.x, size.width / 2, bounds.minX, bounds.maxX),
                       y: axis(point.y, size.height / 2, bounds.minY, bounds.maxY))
    }

    static func isAtRest(_ bodies: [UUID: Body]) -> Bool {
        bodies.values.allSatisfy { hypot($0.velocity.dx, $0.velocity.dy) < 1 }
    }

    /// New words are born together at `origin`. The `core` (the word that inherits a removed
    /// glass identity) stays there; the others leave on distinct radial impulses whose
    /// directions and strengths vary slightly, so the budding never looks mechanical.
    static func spawn(_ ids: [UUID], core: UUID?, at origin: CGPoint, seed: UUID) -> [UUID: Body] {
        let bytes = withUnsafeBytes(of: seed.uuid) { Array($0) }
        let others = ids.filter { $0 != core }
        let base = Double(bytes[0]) / 256 * 2 * .pi
        var bodies: [UUID: Body] = [:]
        if let core { bodies[core] = Body(position: origin) }
        for (k, id) in others.enumerated() {
            let jitter = (Double(bytes[(k + 1) % 16]) / 255 - 0.5) * 0.7
            let angle = base + 2 * .pi * Double(k) / Double(others.count) + jitter
            let speed = spawnSpeed * (1 - 0.12 * CGFloat(k % 4))
            let direction = CGVector(dx: cos(angle), dy: sin(angle))
            bodies[id] = Body(position: CGPoint(x: origin.x + direction.dx, y: origin.y + direction.dy),
                              velocity: CGVector(dx: direction.dx * speed, dy: direction.dy * speed))
        }
        return bodies
    }

    /// Idle float: a shared period keeps every word in rhythm; the phase tells families apart.
    static func orbit(phase: Double, time: TimeInterval, amplitude: CGFloat = orbitAmplitude) -> CGVector {
        let angle = 2 * .pi * time / orbitPeriod + phase
        return CGVector(dx: amplitude * cos(angle), dy: amplitude * 0.6 * sin(angle))
    }
}

extension CGVector {
    static func * (lhs: CGVector, rhs: CGFloat) -> CGVector { CGVector(dx: lhs.dx * rhs, dy: lhs.dy * rhs) }
    static func += (lhs: inout CGVector, rhs: CGVector) { lhs = CGVector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy) }
    static func -= (lhs: inout CGVector, rhs: CGVector) { lhs = CGVector(dx: lhs.dx - rhs.dx, dy: lhs.dy - rhs.dy) }
}
