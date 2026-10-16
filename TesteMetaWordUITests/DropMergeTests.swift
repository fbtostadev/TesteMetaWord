import XCTest

@MainActor final class DropMergeTests: XCTestCase {
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
        let from = CGPoint(x: source.frame.midX, y: source.frame.midY)
        let to = CGPoint(x: target.frame.midX, y: target.frame.midY)
        let length = hypot(from.x - to.x, from.y - to.y)
        let direction = CGVector(dx: (from.x - to.x) / length, dy: (from.y - to.y) / length)
        var near: CGFloat = 0, far: CGFloat = length
        for _ in 0..<20 {
            let mid = (near + far) / 2
            let center = CGPoint(x: to.x + direction.dx * mid, y: to.y + direction.dy * mid)
            let moved = CGRect(x: center.x - source.frame.width / 2, y: center.y - source.frame.height / 2, width: source.frame.width, height: source.frame.height)
            if capsuleGap(moved, target.frame) < 6 { near = mid } else { far = mid }
        }
        let origin = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = origin.withOffset(CGVector(dx: to.x + direction.dx * far - from.x, dy: to.y + direction.dy * far - from.y))
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
