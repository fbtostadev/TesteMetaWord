import SwiftUI
import UIKit

/// Observes every finger on the canvas without consuming touches, so chips keep their own
/// buttons and drags. SwiftUI reports neither resting fingers nor how many are down; the pinch
/// needs both. Points are in window coordinates (SwiftUI `.global`).
struct TouchTracker: UIGestureRecognizerRepresentable {
    let onChange: ([ObjectIdentifier: CGPoint]) -> Void

    func makeUIGestureRecognizer(context: Context) -> Observer {
        let observer = Observer()
        observer.onChange = onChange
        observer.cancelsTouchesInView = false
        observer.delaysTouchesBegan = false
        observer.delaysTouchesEnded = false
        observer.delegate = context.coordinator
        return observer
    }

    func updateUIGestureRecognizer(_ recognizer: Observer, context: Context) {
        recognizer.onChange = onChange
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }

    /// Never leaves `.possible`, so it can't cancel or delay any other gesture; UIKit fails it
    /// when the last finger lifts.
    final class Observer: UIGestureRecognizer {
        var onChange: ([ObjectIdentifier: CGPoint]) -> Void = { _ in }
        private var active: Set<UITouch> = []

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            active.formUnion(touches.filter { $0.type == .direct })
            report()
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { report() }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            active.subtract(touches)
            report()
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
            active.subtract(touches)
            report()
        }
        override func reset() {
            if !active.isEmpty { active = []; report() }
        }

        private func report() {
            onChange(Dictionary(uniqueKeysWithValues: active.map { (ObjectIdentifier($0), $0.location(in: nil)) }))
        }
    }
}
