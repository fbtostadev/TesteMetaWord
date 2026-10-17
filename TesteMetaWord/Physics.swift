import CoreGraphics
import Foundation

/// Pure 2D physics for the organic composition. Bodies are capsule centers in canvas points.
/// The focus (optical center) is pulled to the canvas center; every other word is pulled to a
/// slot on the ring of its atmosphere zone (see `targets`), and repulsion keeps cells from
/// touching. The view freezes the physics during a gesture and adds the idle orbit on top.
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
    static let rampDuration: CGFloat = 0.7

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

    /// Advances every body by `dt`. `zones` gives each non-focus word its atmosphere zone.
    static func step(_ bodies: inout [UUID: Body], sizes: [UUID: CGSize], focus: UUID?, zones: [UUID: Int], center: CGPoint, bounds: CGRect, dt: CGFloat) {
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
        for (id, target) in targets(bodies, sizes: sizes, focus: focus, zones: zones, center: center) {
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

    /// Where each word wants to be. The focus goes to the canvas center. Occupied zones take
    /// rings around the focus in order (see `zoneGap`). On a ring, words keep their current
    /// angular order and are packed by the room they really take, at least `restGap` apart, with
    /// the spare room shared evenly and the whole ring turned to move them as little as possible.
    /// Words that do not fit (the narrowest first, so text-dense words stay central) overflow to the next ring, so a crowded zone or
    /// a wide focus never pins words against each other. An outer ring also clears the words of
    /// the inner ones: a word whose spot is taken slides along its ring to a free one, so rings
    /// interleave (beside a wide focus words sit side by side, wider than the ring spacing).
    static func targets(_ bodies: [UUID: Body], sizes: [UUID: CGSize], focus: UUID?, zones: [UUID: Int], center: CGPoint) -> [UUID: CGPoint] {
        guard let focus, let core = bodies[focus]?.position, let coreSize = sizes[focus] else { return [:] }
        var targets = [focus: center]
        var ring = Ring(core: core, coreSize: coreSize, sizes: sizes)
        var overflow: [UUID] = []
        var level = 0
        for zone in Set(zones.values).sorted() {
            let members = overflow + zones.keys.filter { zones[$0] == zone && bodies[$0] != nil && sizes[$0] != nil }
            overflow = ring.lay(members, bodies: bodies, gap: restGap + CGFloat(level) * zoneSpacing, into: &targets)
            level += 1
        }
        while !overflow.isEmpty, level < 12 {
            overflow = ring.lay(overflow, bodies: bodies, gap: restGap + CGFloat(level) * zoneSpacing, into: &targets)
            level += 1
        }
        return targets
    }

    /// Slots on one ring around the focus, at a surface gap from it.
    private struct Ring {
        let core: CGPoint
        let coreSize: CGSize
        let sizes: [UUID: CGSize]
        /// Words already laid on inner rings, which outer ones keep `restGap` away from.
        var placed: [CGRect] = []

        /// Lays `members` on the ring at `gap` and returns the ones that do not fit.
        mutating func lay(_ members: [UUID], bodies: [UUID: Body], gap: CGFloat, into targets: inout [UUID: CGPoint]) -> [UUID] {
            guard !members.isEmpty else { return [] }
            func angle(_ id: UUID) -> CGFloat { atan2(bodies[id]!.position.y - core.y, bodies[id]!.position.x - core.x) }
            var kept = members.sorted { angle($0) < angle($1) }
            var overflow: [UUID] = []
            // Move the narrowest out (ties by id, so the choice holds from frame to frame) until the
            // rest fit: words dense with text stay closer to the focus.
            while kept.count > 1, walk(kept, from: angle(kept[0]), share: 0, gap: gap).turn > 2 * .pi {
                let narrowest = kept.min { (sizes[$0]!.width, $0.uuidString) < (sizes[$1]!.width, $1.uuidString) }!
                kept.removeAll { $0 == narrowest }
                overflow.append(narrowest)
            }
            // Plan from the first word, turn the plan toward where the words are, then plan again
            // from that turned start so every gap is measured where the words will actually sit.
            var start = angle(kept[0])
            let offsets = zip(kept, plan(kept, from: start, gap: gap)).map { angle($0) - $1 }
            start += atan2(offsets.map { sin($0) }.reduce(0, +), offsets.map { cos($0) }.reduce(0, +))
            var laid: [CGRect] = []
            for (id, a) in zip(kept, plan(kept, from: start, gap: gap)) {
                targets[id] = point(sizes[id]!, a, gap: gap)
                laid.append(rect(targets[id]!, sizes[id]!))
            }
            placed += laid
            return overflow
        }

        /// Angles from `start`: each word right after the previous one plus a share of the spare
        /// room. The share is the largest that still closes the ring, found by bisection, because
        /// one angle is worth more room at the ends of a wide focus than along its sides.
        private func plan(_ members: [UUID], from start: CGFloat, gap: CGFloat) -> [CGFloat] {
            guard members.count > 1 else { return [start] }
            var low: CGFloat = 0, high = 2 * .pi / CGFloat(members.count)
            for _ in 0..<6 {
                let mid = (low + high) / 2
                if walk(members, from: start, share: mid, gap: gap).turn <= 2 * .pi { low = mid } else { high = mid }
            }
            return walk(members, from: start, share: low, gap: gap).angles
        }

        /// Lays the words one after another from `start`, each the smallest turn after the previous
        /// one that keeps `restGap` between them, plus `share`; a word whose spot is taken by a word
        /// of an inner ring slides along the ring to the next free spot, so rings interleave instead
        /// of stacking in spokes. `turn` runs back to the first word: the ring closes when it is at
        /// most a full turn.
        private func walk(_ members: [UUID], from start: CGFloat, share: CGFloat, gap: CGFloat) -> (angles: [CGFloat], turn: CGFloat) {
            let sized = members.map { sizes[$0]! }
            let first = free(sized[0], from: start, gap: gap)
            guard members.count > 1 else { return ([first], 0) }
            var angles: [CGFloat] = [], a = first
            for k in members.indices {
                if k > 0 { a = free(sized[k], from: a, gap: gap) }
                angles.append(a)
                let next = sized[(k + 1) % members.count]
                let here = rect(ringPoint(sized[k], a, gap: gap), sized[k])
                var near: CGFloat = 0, far = CGFloat.pi
                for _ in 0..<10 {
                    let mid = (near + far) / 2
                    if signedDistance(here, rect(ringPoint(next, a + mid, gap: gap), next)) < restGap { near = mid } else { far = mid }
                }
                a += far + share
            }
            return (angles, a - first)
        }

        /// The first angle from `a` onward where a word of `size` on the ring clears the words of
        /// inner rings: a coarse sweep, then bisection, so the spot moves smoothly with `a`.
        private func free(_ size: CGSize, from a: CGFloat, gap: CGFloat) -> CGFloat {
            func taken(_ angle: CGFloat) -> Bool {
                let r = rect(ringPoint(size, angle, gap: gap), size)
                return placed.contains { signedDistance(r, $0) < restGap }
            }
            guard taken(a) else { return a }
            var near = a
            for _ in 0..<105 {
                let far = near + 0.06
                guard taken(far) else {
                    var low = near, high = far
                    for _ in 0..<8 {
                        let mid = (low + high) / 2
                        if taken(mid) { low = mid } else { high = mid }
                    }
                    return high
                }
                near = far
            }
            return a
        }

        /// Center of a word of `size` on the ring in direction `angle`: exactly `gap` from the
        /// focus surface (capsules are horizontal segments with round caps).
        private func ringPoint(_ size: CGSize, _ angle: CGFloat, gap: CGFloat) -> CGPoint {
            let cx = abs(cos(angle)), cy = abs(sin(angle))
            let span = max(0, size.width / 2 - size.height / 2) + max(0, coreSize.width / 2 - coreSize.height / 2)
            let reach = gap + size.height / 2 + coreSize.height / 2
            var t = cy > 0.0001 ? reach / cy : .infinity
            if t * cx > span { t = span * cx + sqrt(max(0, reach * reach - span * span * cy * cy)) }
            return CGPoint(x: core.x + cos(angle) * t, y: core.y + sin(angle) * t)
        }

        /// The ring point, or, when a whole ring is taken and a word stayed on a blocked spot,
        /// the nearest point outward along the same ray that clears the inner words.
        private func point(_ size: CGSize, _ angle: CGFloat, gap: CGFloat) -> CGPoint {
            let base = ringPoint(size, angle, gap: gap)
            func at(_ t: CGFloat) -> CGPoint { CGPoint(x: base.x + cos(angle) * t, y: base.y + sin(angle) * t) }
            func blocked(_ t: CGFloat) -> Bool { placed.contains { signedDistance(rect(at(t), size), $0) < restGap } }
            guard blocked(0) else { return base }
            var near: CGFloat = 0, far: CGFloat = 2000
            for _ in 0..<12 {
                let mid = (near + far) / 2
                if blocked(mid) { near = mid } else { far = mid }
            }
            return at(far)
        }
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
