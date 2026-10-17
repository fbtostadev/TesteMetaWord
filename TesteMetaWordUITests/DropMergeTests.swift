import XCTest

/// Minimal interaction check in one launch: the whole drag-and-drop gesture (shallow and deep),
/// a fusion from the outer zone, Undo and the long-press split.
@MainActor final class DropMergeTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testBasicComposition() {
        let app = XCUIApplication()
        app.launch()
        let querer = app.buttons["chip-querer"], ir = app.buttons["chip-ir"]
        XCTAssertTrue(querer.waitForExistence(timeout: 5))
        let undo = app.buttons["Desfazer"]

        // Stopping 6 pt from the surface, inside the bridge range but without overlap, never fuses.
        waitUntilSettled(ir)
        shallowDrop(ir, onto: querer, in: app)
        XCTAssertFalse(app.buttons["chip-Quero ir"].waitForExistence(timeout: 1))
        XCTAssertFalse(undo.isEnabled)

        // Dropping deep fuses without another tap; the suggestions bud.
        waitUntilSettled(ir)
        drag(querer, to: ir, in: app)
        let focus = app.buttons["chip-Quero ir"]
        XCTAssertTrue(focus.waitForExistence(timeout: 5), "Soltar sobre ir deve gerar Quero ir sem outro toque")
        XCTAssertTrue(app.buttons["chip-agora"].exists && app.buttons["chip-depois"].exists)

        // comer now sits in the outer zone and still fuses with the focus.
        let comer = app.buttons["chip-comer"]
        waitUntilSettled(comer)
        drag(comer, to: focus, in: app)
        let weak = app.buttons["chip-Quero ir e comer"]
        XCTAssertTrue(weak.waitForExistence(timeout: 5), "Uma palavra da zona externa também se funde")

        undo.tap()
        XCTAssertTrue(focus.waitForExistence(timeout: 3))
        XCTAssertTrue(comer.exists)

        // Holding the latest result splits it back into its origins.
        waitUntilSettled(focus)
        focus.press(forDuration: 1.0)
        XCTAssertTrue(querer.waitForExistence(timeout: 3), "Segurar o resultado deve dividi-lo")
        XCTAssertTrue(ir.exists)
        XCTAssertFalse(undo.isEnabled)
    }

    /// Waits until the physics has settled `element`: only the slow idle orbit (about 1 pt per
    /// quarter second) remains. Faster than a fixed sleep and safer than none.
    private func waitUntilSettled(_ element: XCUIElement, timeout: TimeInterval = 4) {
        var last = element.frame
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            let now = element.frame
            if hypot(now.midX - last.midX, now.midY - last.midY) < 2 { return }
            last = now
        }
    }

    /// Native glass can change accessibility frames while surfaces join. Resolve both points
    /// before the gesture and keep them in the app's coordinate space through release.
    private func drag(_ source: XCUIElement, to target: XCUIElement, in app: XCUIApplication) {
        let a = source.frame, b = target.frame
        point(app, CGPoint(x: a.midX, y: a.midY))
            .press(forDuration: 0.05, thenDragTo: point(app, CGPoint(x: b.midX, y: b.midY)), withVelocity: .slow, thenHoldForDuration: 0)
    }

    /// Drags `source` toward `target` from its own side and stops 6 pt from the surface.
    /// Frames are sampled once: repeated queries would let the idle orbit move the inputs.
    private func shallowDrop(_ source: XCUIElement, onto target: XCUIElement, in app: XCUIApplication) {
        let sourceFrame = source.frame, targetFrame = target.frame
        let from = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        let to = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        let length = hypot(from.x - to.x, from.y - to.y)
        let direction = CGVector(dx: (from.x - to.x) / length, dy: (from.y - to.y) / length)
        var near: CGFloat = 0, far: CGFloat = length
        for _ in 0..<20 {
            let mid = (near + far) / 2
            let center = CGPoint(x: to.x + direction.dx * mid, y: to.y + direction.dy * mid)
            let moved = CGRect(x: center.x - sourceFrame.width / 2, y: center.y - sourceFrame.height / 2, width: sourceFrame.width, height: sourceFrame.height)
            if capsuleGap(moved, targetFrame) < 6 { near = mid } else { far = mid }
        }
        let end = CGPoint(x: to.x + direction.dx * far, y: to.y + direction.dy * far)
        point(app, from).press(forDuration: 0.05, thenDragTo: point(app, end), withVelocity: .slow, thenHoldForDuration: 1)
    }

    private func point(_ app: XCUIApplication, _ location: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: location.x - app.frame.minX, dy: location.y - app.frame.minY))
    }

    /// Surface distance between two horizontal capsules (same rule as `Physics.signedDistance`).
    private func capsuleGap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let ar = a.height / 2, br = b.height / 2
        let horizontal = max(0, max(a.minX + ar, b.minX + br) - min(a.maxX - ar, b.maxX - br))
        return hypot(horizontal, a.midY - b.midY) - ar - br
    }
}
