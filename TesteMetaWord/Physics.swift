import CoreGraphics
import Foundation

/// Pure 2D physics for the organic composition. Bodies are capsule centers in canvas points.
/// The focus (optical center) is pulled to the canvas center; every other word is pulled to a
/// slot on the ring of its atmosphere zone (see `targets`), and repulsion keeps cells from
/// touching. The view freezes the physics during a gesture and adds the idle orbit on top.
enum Physics {
    /// Resting gap between surfaces. Larger than the GlassEffectContainer spacing (32 pt),
    /// so words never bridge at rest.
    static let restGap: CGFloat = 40
    static let stiffness: CGFloat = 150
    /// Each zone sits one word layer (56 pt + rest gap) beyond the previous one.
    static let zoneSpacing: CGFloat = 96
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
    }

    /// Target surface distance from the focus for atmosphere zone 1 (inner), 2 or 3 (outer).
    static func zoneGap(_ zone: Int) -> CGFloat { restGap + CGFloat(zone - 1) * zoneSpacing }

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
            acceleration[id]! += CGVector(dx: target.x - p.x, dy: target.y - p.y) * pull
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
            bodies[id] = body
        }
    }

    /// Where each word wants to be. The focus goes to the canvas center. Words of one zone get
    /// evenly spaced angles around the focus, in their current angular order and rotated to move
    /// them as little as possible; each slot sits at the zone's surface gap from the focus.
    static func targets(_ bodies: [UUID: Body], sizes: [UUID: CGSize], focus: UUID?, zones: [UUID: Int], center: CGPoint) -> [UUID: CGPoint] {
        guard let focus, let core = bodies[focus]?.position, let coreSize = sizes[focus] else { return [:] }
        var targets = [focus: center]
        for zone in Set(zones.values) {
            let members = zones.keys
                .filter { zones[$0] == zone && bodies[$0] != nil && sizes[$0] != nil }
                .map { id in (id: id, angle: atan2(bodies[id]!.position.y - core.y, bodies[id]!.position.x - core.x)) }
                .sorted { $0.angle < $1.angle }
            let step = 2 * CGFloat.pi / CGFloat(members.count)
            let offsets = members.enumerated().map { k, m in m.angle - step * CGFloat(k) }
            let rotation = atan2(offsets.map { sin($0) }.reduce(0, +), offsets.map { cos($0) }.reduce(0, +))
            for (k, member) in members.enumerated() {
                let angle = rotation + step * CGFloat(k)
                let direction = CGVector(dx: cos(angle), dy: sin(angle))
                let size = sizes[member.id]!
                // Bisection for the distance that leaves exactly the zone gap to the focus surface.
                var near: CGFloat = 0, far: CGFloat = 2000
                for _ in 0..<18 {
                    let mid = (near + far) / 2
                    let point = CGPoint(x: core.x + direction.dx * mid, y: core.y + direction.dy * mid)
                    if signedDistance(rect(point, size), rect(core, coreSize)) < zoneGap(zone) { near = mid } else { far = mid }
                }
                targets[member.id] = CGPoint(x: core.x + direction.dx * far, y: core.y + direction.dy * far)
            }
        }
        return targets
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
