import XCTest

@MainActor final class DropMergeTests: XCTestCase {
    /// Attachments cover occupied/empty inner zones and Undo. The marker lets a host-side
    /// simctl capture run while XCTest holds the actual drag down for eight seconds.
    func testAtmosphereThroughThreeDragsAndUndo() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["chip-querer"].waitForExistence(timeout: 5))
        sleep(2)
        capture(app, name: "atmosphere-initial")

        let source = app.buttons["chip-eu"]
        let target = app.buttons["chip-querer"]
        print("ATMOSPHERE_CAPTURE_ARMED_BEGIN")
        drag(source, to: target, in: app, hold: 8)
        print("ATMOSPHERE_CAPTURE_ARMED_END")
        let first = app.buttons["chip-Eu quero"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        guard first.exists else { return }
        sleep(2)
        capture(app, name: "atmosphere-first-fusion")

        drag(app.buttons["chip-comer"], to: first, in: app)
        let second = app.buttons["chip-Eu quero comer"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        guard second.exists else { return }
        sleep(2)
        drag(app.buttons["chip-agora"], to: second, in: app)
        let phrase = app.buttons["chip-Eu quero comer agora"]
        XCTAssertTrue(phrase.waitForExistence(timeout: 5))
        guard phrase.exists else { return }
        XCTAssertTrue(app.buttons["chip-aqui"].exists)
        XCTAssertTrue(app.buttons["chip-ali"].exists)
        sleep(2)
        assertSeparatedFromFocus(phrase, in: app)
        capture(app, name: "atmosphere-long-phrase")

        print("ATMOSPHERE_CAPTURE_UNDO_BEGIN")
        app.buttons["Desfazer"].tap()
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chip-agora"].exists)
        XCTAssertFalse(phrase.exists)
        XCTAssertFalse(app.buttons["chip-aqui"].exists)
        XCTAssertFalse(app.buttons["chip-ali"].exists)
        sleep(2)
        assertSeparatedFromFocus(second, in: app)
        capture(app, name: "atmosphere-undo")
    }

    /// Native glass can change accessibility frames while surfaces join. Resolve both points
    /// before the gesture and keep them in the app's coordinate space through release.
    private func drag(_ source: XCUIElement, to target: XCUIElement, in app: XCUIApplication, hold: TimeInterval = 0) {
        let a = source.frame, b = target.frame, bounds = app.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: a.midX - bounds.minX, dy: a.midY - bounds.minY))
        let end = origin.withOffset(CGVector(dx: b.midX - bounds.minX, dy: b.midY - bounds.minY))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: hold)
    }

    private func assertSeparatedFromFocus(_ focus: XCUIElement, in app: XCUIApplication) {
        let frame = focus.frame, identifier = focus.identifier
        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chip-")).allElementsBoundByIndex
        for chip in chips where chip.identifier != identifier {
            XCTAssertGreaterThanOrEqual(capsuleGap(frame, chip.frame), 0,
                                        "\(chip.identifier) deve ficar legível fora do foco após o equilíbrio")
        }
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDropMergesWithoutAnotherTapAndUndoRestoresWords() {
        let app = XCUIApplication()
        app.launch()
        let source = app.buttons["chip-querer"]
        let target = app.buttons["chip-ir"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.press(forDuration: 0.05, thenDragTo: target)
        let result = app.buttons["chip-Quero ir"]
        XCTAssertTrue(result.waitForExistence(timeout: 5), "Soltar sobre ir deve gerar Quero ir sem outro toque")
        guard result.exists else { return }
        XCTAssertTrue(app.buttons["chip-agora"].exists)
        XCTAssertTrue(app.buttons["chip-depois"].exists)
        XCTAssertFalse(source.exists)
        XCTAssertFalse(target.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Fusão após soltura"
        attachment.lifetime = .keepAlways
        add(attachment)
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
        origin.press(forDuration: 0.05, thenDragTo: destination)
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
