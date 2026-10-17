import XCTest

@MainActor final class DropMergeTests: XCTestCase {
    /// Attachments cover occupied/empty inner zones and Undo. The marker lets a host-side
    /// simctl capture run while XCTest holds the actual drag down for eight seconds.
    override func setUp() async throws {
        continueAfterFailure = false
        await MainActor.run { XCUIDevice.shared.orientation = .portrait }
    }

    func testAtmosphereThroughThreeDragsAndUndo() {
        atmospherePath(renderer: "metal", compareAndRotate: true)
    }

    func testRendererSwitchPreservesInitialWords() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["chip-querer"].waitForExistence(timeout: 5))
        let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chip-"))
        let initial = Set(chips.allElementsBoundByIndex.map(\.identifier))
        XCTAssertEqual(initial.count, 6)
        selectRenderer("gradients", in: app)
        selectRenderer("metal", in: app)
        XCTAssertEqual(Set(chips.allElementsBoundByIndex.map(\.identifier)), initial)
        XCTAssertFalse(app.buttons["Desfazer"].isEnabled)
    }

    func testGradientAtmosphereThroughThreeDragsAndUndo() {
        atmospherePath(renderer: "gradients", compareAndRotate: false)
    }

    private func atmospherePath(renderer: String, compareAndRotate: Bool) {
        print("ATMOSPHERE_MODE=\(renderer)")
        let app = XCUIApplication()
        app.launchArguments = ["--atmosphere-renderer=\(renderer)"]
        app.launch()
        selectRenderer(renderer, in: app)
        XCTAssertTrue(app.buttons["chip-querer"].waitForExistence(timeout: 5))
        sleep(2)
        capture(app, name: "atmosphere-initial-\(renderer)")

        let source = app.buttons["chip-eu"]
        let target = app.buttons["chip-querer"]
        print("ATMOSPHERE_CAPTURE_ARMED_BEGIN")
        drag(source, to: target, in: app, hold: 8, penetration: 0.60)
        print("ATMOSPHERE_CAPTURE_ARMED_END")
        let first = app.buttons["chip-Eu quero"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        guard first.exists else { return }
        sleep(2)
        capture(app, name: "atmosphere-first-fusion-\(renderer)")

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
        capture(app, name: "atmosphere-long-phrase-\(renderer)")

        if compareAndRotate {
            let chips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chip-")).allElementsBoundByIndex
            let before = Dictionary(uniqueKeysWithValues: chips.map { ($0.identifier, $0.frame) })
            selectRenderer("gradients", in: app)
            XCTAssertTrue(phrase.exists)
            XCTAssertTrue(app.buttons["Desfazer"].isEnabled)
            let after = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chip-")).allElementsBoundByIndex
            XCTAssertEqual(Set(before.keys), Set(after.map(\.identifier)))
            for chip in after {
                let old = before[chip.identifier]!
                XCTAssertLessThan(hypot(old.midX - chip.frame.midX, old.midY - chip.frame.midY), 24,
                                  "Trocar o desenho deve preservar os corpos")
            }
            capture(app, name: "atmosphere-comparison-gradients")
            selectRenderer("metal", in: app)
            capture(app, name: "atmosphere-comparison-metal")
            XCUIDevice.shared.orientation = .landscapeLeft
            print("ATMOSPHERE_CAPTURE_LANDSCAPE_BEGIN")
            sleep(2)
            assertSeparatedFromFocus(phrase, in: app)
            capture(app, name: "atmosphere-landscape-metal")
            XCUIDevice.shared.orientation = .portrait
            sleep(2)
        }

        print("ATMOSPHERE_CAPTURE_UNDO_BEGIN")
        app.buttons["Desfazer"].tap()
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chip-agora"].exists)
        XCTAssertFalse(phrase.exists)
        XCTAssertFalse(app.buttons["chip-aqui"].exists)
        XCTAssertFalse(app.buttons["chip-ali"].exists)
        sleep(2)
        assertSeparatedFromFocus(second, in: app)
        capture(app, name: "atmosphere-undo-\(renderer)")
    }

    private func selectRenderer(_ renderer: String, in app: XCUIApplication) {
        app.buttons["Calibração"].tap()
        let picker = app.buttons["atmosphere-renderer"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.tap()
        app.buttons[renderer == "metal" ? "Metal" : "Gradientes"].tap()
        capture(app, name: "atmosphere-panel-\(renderer)")
        let status = app.staticTexts["atmosphere-renderer-status"]
        let ready = NSPredicate(format: "label == %@", renderer == "metal" ? "Metal ativo" : "Gradientes ativos")
        expectation(for: ready, evaluatedWith: status)
        waitForExpectations(timeout: 10)
        app.buttons["OK"].tap()
    }

    /// Native glass can change accessibility frames while surfaces join. Resolve both points
    /// before the gesture and keep them in the app's coordinate space through release.
    private func drag(_ source: XCUIElement, to target: XCUIElement, in app: XCUIApplication,
                      hold: TimeInterval = 0, penetration: CGFloat? = nil) {
        let a = source.frame, b = target.frame, bounds = app.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: a.midX - bounds.minX, dy: a.midY - bounds.minY))
        var point = CGPoint(x: b.midX, y: b.midY)
        if let penetration {
            // Keep both words visible in the armed capture, instead of burying one at the
            // other's center. Sixty percent leaves margin above the 45% gesture threshold.
            let length = max(1, hypot(a.midX - b.midX, a.midY - b.midY))
            let direction = CGVector(dx: (a.midX - b.midX) / length, dy: (a.midY - b.midY) / length)
            var near: CGFloat = 0, far = length
            for _ in 0..<20 {
                let mid = (near + far) / 2
                let moved = CGRect(x: b.midX + direction.dx * mid - a.width / 2,
                                   y: b.midY + direction.dy * mid - a.height / 2,
                                   width: a.width, height: a.height)
                if capsuleGap(moved, b) < -penetration * min(a.height, b.height) { near = mid } else { far = mid }
            }
            point = CGPoint(x: b.midX + direction.dx * far, y: b.midY + direction.dy * far)
        }
        let end = origin.withOffset(CGVector(dx: point.x - bounds.minX, dy: point.y - bounds.minY))
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
        // App snapshots can retain the portrait crop during rotation; capture the display.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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

    /// XCTest lands both pinch fingers inside one element, so this covers a real two-finger
    /// gesture where both fingers rest on the same bubble: no pinch, no fusion, no split.
    /// A pinch across two bubbles is validated by hand (see README).
    func testTwoFingersOnOneBubbleDoNotPinchOrSplit() {
        let app = XCUIApplication()
        app.launch()
        let source = app.buttons["chip-querer"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.press(forDuration: 0.05, thenDragTo: app.buttons["chip-ir"])
        let result = app.buttons["chip-Quero ir"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        guard result.exists else { return }
        sleep(2)
        let count = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chip-")).count
        result.pinch(withScale: 0.6, velocity: -0.5)
        sleep(1)
        XCTAssertTrue(result.exists, "Dois dedos não devem dividir o resultado")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chip-")).count, count)
        XCTAssertTrue(app.buttons["Desfazer"].isEnabled)
    }

    /// A word that is not the latest result has nothing to split.
    func testLongPressOnAnIndivisibleWordKeepsTheComposition() {
        let app = XCUIApplication()
        app.launch()
        let focus = app.buttons["chip-querer"]
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
        sleep(2)
        let count = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chip-")).count
        focus.press(forDuration: 1.0)
        XCTAssertTrue(focus.exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chip-")).count, count)
        XCTAssertFalse(app.buttons["Desfazer"].isEnabled)
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
        print("ATMOSPHERE_MODE=metal")
        print("ATMOSPHERE_CAPTURE_RESISTANCE_BEGIN")
        origin.press(forDuration: 0.05, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 4)
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
