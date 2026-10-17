import CoreGraphics
import Foundation

/// Recognizes a shake of the dragged bubble: quick reversals of direction along either axis.
/// A drag toward a target, even with a correction, reverses once or twice and slowly; a shake
/// reverses `reversals` times within `window`, each swing at least `travel` long. Fires once.
struct ShakeDetector {
    static let travel: CGFloat = 28
    static let reversals = 3
    static let window: TimeInterval = 0.8

    private var axes = [Axis(), Axis()]
    private var fired = false

    /// Feeds the finger position; true exactly once, when the shake is recognized.
    mutating func add(_ point: CGPoint, time: TimeInterval) -> Bool {
        guard !fired else { return false }
        let count = max(axes[0].add(point.x, time), axes[1].add(point.y, time))
        fired = count >= Self.reversals
        return fired
    }

    private struct Axis {
        /// Farthest point of the current swing.
        var extreme: CGFloat?
        /// Direction of the current swing; 0 until the first swing is long enough.
        var sign: CGFloat = 0
        var reversals: [TimeInterval] = []

        mutating func add(_ value: CGFloat, _ time: TimeInterval) -> Int {
            reversals.removeAll { time - $0 > ShakeDetector.window }
            guard let extreme else {
                self.extreme = value
                return 0
            }
            let delta = value - extreme
            if sign == 0 {
                if abs(delta) >= ShakeDetector.travel {
                    sign = delta > 0 ? 1 : -1
                    self.extreme = value
                }
            } else if delta * sign > 0 {
                self.extreme = value
            } else if abs(delta) >= ShakeDetector.travel {
                sign = -sign
                self.extreme = value
                reversals.append(time)
            }
            return reversals.count
        }
    }
}
