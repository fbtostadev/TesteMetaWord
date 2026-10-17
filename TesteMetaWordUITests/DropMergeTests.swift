import XCTest

/// Minimal interaction check in one launch: the whole drag-and-drop gesture (shallow and deep),
/// the gap a drop on the BubbleKey chooses (left and right of the same bubble), a fusion from the
/// outer zone, Undo, pulling a word out of the phrase and putting it back, and the long-press split.
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

        // Over the BubbleKey, the finger chooses the gap: the order the person chose is final.
        let eu = app.buttons["chip-eu"]
        for (side, result) in [(CGFloat(-1), "Eu quero ir"), (1, "Quero ir eu")] {
            waitUntilSettled(eu)
            waitUntilSettled(focus)
            drop(eu, onto: focus, side: side, in: app)
            XCTAssertTrue(app.buttons["chip-\(result)"].waitForExistence(timeout: 5), "Soltar \(side < 0 ? "à esquerda" : "à direita") deve gerar \(result)")
            undo.tap()
            XCTAssertTrue(focus.waitForExistence(timeout: 3))
        }

        // comer now sits in the outer zone and still fuses with the focus.
        let comer = app.buttons["chip-comer"]
        waitUntilSettled(comer)
        waitUntilSettled(focus)
        drop(comer, onto: focus, side: 1, in: app)
        let weak = app.buttons["chip-Quero ir e comer"]
        XCTAssertTrue(weak.waitForExistence(timeout: 5), "Uma palavra da zona externa também se funde")

        undo.tap()
        XCTAssertTrue(focus.waitForExistence(timeout: 3))
        XCTAssertTrue(comer.exists)

        // Holding a word of the phrase and pulling takes just that word out; putting it back on the
        // BubbleKey is a new insertion, and Undo goes back through both acts.
        waitUntilSettled(focus)
        pullOut(focus, at: 0.85, to: CGPoint(x: app.frame.minX + 100, y: app.frame.maxY - 200), in: app)
        let rest = app.buttons["chip-Quero"]
        XCTAssertTrue(rest.waitForExistence(timeout: 5), "Puxar a palavra deve deixar o resto da frase na BubbleKey")
        XCTAssertTrue(ir.waitForExistence(timeout: 5), "A palavra puxada vira uma bolha própria")
        XCTAssertFalse(focus.exists)
        waitUntilSettled(ir)
        waitUntilSettled(rest)
        drop(ir, onto: rest, side: 1, in: app)
        XCTAssertTrue(focus.waitForExistence(timeout: 5), "Soltar a palavra à direita da BubbleKey deve devolvê-la à frase")
        undo.tap()
        XCTAssertTrue(rest.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertTrue(focus.waitForExistence(timeout: 3))
        XCTAssertFalse(ir.exists)

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

    /// Rests a finger on `target` at `x` (0 … 1 across it) for 0.3 s, longer than a drag's grace and
    /// shorter than the long press that splits it, and then pulls to `end`.
    private func pullOut(_ target: XCUIElement, at x: CGFloat, to end: CGPoint, in app: XCUIApplication) {
        let frame = target.frame
        point(app, CGPoint(x: frame.minX + frame.width * x, y: frame.midY))
            .press(forDuration: 0.3, thenDragTo: point(app, end), withVelocity: .slow, thenHoldForDuration: 0)
    }

    /// Drags `source` until the finger rests 12 pt inside the left (`side` -1) or right (1) end
    /// of `target`, which picks the gap at that end of its phrase.
    private func drop(_ source: XCUIElement, onto target: XCUIElement, side: CGFloat, in app: XCUIApplication) {
        let a = source.frame, b = target.frame
        let end = CGPoint(x: side < 0 ? b.minX + 12 : b.maxX - 12, y: b.midY)
        point(app, CGPoint(x: a.midX, y: a.midY))
            .press(forDuration: 0.05, thenDragTo: point(app, end), withVelocity: .slow, thenHoldForDuration: 0)
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
