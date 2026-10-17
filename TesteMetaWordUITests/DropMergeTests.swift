import XCTest

/// Minimal interaction checks: the whole drag-and-drop gesture, Undo and the long-press split.
@MainActor final class DropMergeTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Native glass can change accessibility frames while surfaces join. Resolve both points
    /// before the gesture and keep them in the app's coordinate space through release.
    private func drag(_ source: XCUIElement, to target: XCUIElement, in app: XCUIApplication) {
        let a = source.frame, b = target.frame, bounds = app.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: a.midX - bounds.minX, dy: a.midY - bounds.minY))
        let end = origin.withOffset(CGVector(dx: b.midX - bounds.minX, dy: b.midY - bounds.minY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
    }

    /// Holding the latest result builds tension and splits it at 0.6 s, without another tap.
    func testLongPressSplitsTheLatestResult() {
        let app = XCUIApplication()
        app.launch()
        let source = app.buttons["chip-querer"]
        let target = app.buttons["chip-ir"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.press(forDuration: 0.05, thenDragTo: target)
        let result = app.buttons["chip-Quero ir"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        guard result.exists else { return }
        sleep(2) // let the result settle at the center
        result.press(forDuration: 1.0)
        XCTAssertTrue(source.waitForExistence(timeout: 3), "Segurar o resultado deve dividi-lo")
        XCTAssertTrue(target.exists)
        XCTAssertFalse(result.exists)
        XCTAssertFalse(app.buttons["Desfazer"].isEnabled)
    }

    /// After Quero ir, comer sits in the outer zone (its verb collides) and still fuses by drop.
    func testOuterZoneWordFusesWithTheFocus() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["chip-querer"].waitForExistence(timeout: 5))
        drag(app.buttons["chip-querer"], to: app.buttons["chip-ir"], in: app)
        let focus = app.buttons["chip-Quero ir"]
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
        guard focus.exists else { return }
        sleep(2)
        drag(app.buttons["chip-comer"], to: focus, in: app)
        let weak = app.buttons["chip-Quero ir e comer"]
        XCTAssertTrue(weak.waitForExistence(timeout: 5), "Uma palavra da zona externa também se funde")
        guard weak.exists else { return }
        sleep(2)
        drag(app.buttons["chip-agora"], to: weak, in: app)
        XCTAssertTrue(app.buttons["chip-Quero ir e comer agora"].waitForExistence(timeout: 5))
        app.buttons["Desfazer"].tap()
        XCTAssertTrue(weak.waitForExistence(timeout: 3))
        app.buttons["Desfazer"].tap()
        XCTAssertTrue(focus.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["chip-comer"].exists)
    }

    func testDropMergesWithoutAnotherTapAndUndoRestoresWords() {
        let app = XCUIApplication()
        app.launch()
        let source = app.buttons["chip-querer"]
        let target = app.buttons["chip-ir"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        drag(source, to: target, in: app)
        let result = app.buttons["chip-Quero ir"]
        XCTAssertTrue(result.waitForExistence(timeout: 5), "Soltar sobre ir deve gerar Quero ir sem outro toque")
        guard result.exists else { return }
        XCTAssertTrue(app.buttons["chip-agora"].exists)
        XCTAssertTrue(app.buttons["chip-depois"].exists)
        XCTAssertFalse(source.exists)
        XCTAssertFalse(target.exists)
        app.buttons["Desfazer"].tap()
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        XCTAssertTrue(target.exists)
        XCTAssertFalse(result.exists)
    }

    func testShallowDropDoesNotMerge() {
        let app = XCUIApplication()
        app.launch()
        // Drag the zone word "ir" toward the focus "querer" from its own side, so nothing else
        // lies in between, and stop 6 pt from the surface: inside the native bridge range but
        // without penetration of the capsules.
        let source = app.buttons["chip-ir"]
        let target = app.buttons["chip-querer"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        sleep(2) // let the opening bloom settle
        // Sample once: repeated accessibility queries let the idle orbit move the inputs
        // during bisection. Anchor the destination to the app, not to the moving source.
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
        let origin = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: to.x + direction.dx * far - app.frame.minX, dy: to.y + direction.dy * far - app.frame.minY))
        origin.press(forDuration: 0.05, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertFalse(app.buttons["chip-Quero ir"].waitForExistence(timeout: 1))
        XCTAssertTrue(source.exists)
        XCTAssertTrue(target.exists)
        XCTAssertFalse(app.buttons["Desfazer"].isEnabled)
        // Without a fusion the physics resumes and opens the gap again.
        XCTAssertFalse(source.frame.intersects(target.frame))
    }

    /// Surface distance between two horizontal capsules (same rule as `Physics.signedDistance`).
    private func capsuleGap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let ar = a.height / 2, br = b.height / 2
        let horizontal = max(0, max(a.minX + ar, b.minX + br) - min(a.maxX - ar, b.maxX - br))
        return hypot(horizontal, a.midY - b.midY) - ar - br
    }
}
