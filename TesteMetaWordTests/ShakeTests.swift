import Testing
import CoreGraphics
@testable import TesteMetaWord

@MainActor struct ShakeTests {
    /// Feeds points 0.1 s apart and reports at which index the shake fired, if it did.
    func firing(_ points: [CGPoint], step: Double = 0.1) -> Int? {
        var detector = ShakeDetector()
        for (k, point) in points.enumerated() where detector.add(point, time: Double(k) * step) { return k }
        return nil
    }

    @Test func quickReversalsShakeOnceButADragDoesNot() {
        let zigzag = (0..<8).map { CGPoint(x: $0 % 2 == 0 ? 0 : 40, y: 0) }
        #expect(firing(zigzag) == 4, "three reversals after the first swing")
        #expect(firing((0..<8).map { CGPoint(x: 0, y: $0 % 2 == 0 ? 0 : 40) }) == 4, "vertically too")
        #expect(firing(zigzag, step: 0.5) == nil, "too slow")
        #expect(firing((0..<8).map { CGPoint(x: $0 % 2 == 0 ? 0 : 12, y: 0) }) == nil, "too small")
        #expect(firing((0..<12).map { CGPoint(x: CGFloat($0) * 30, y: CGFloat($0) * 10) }) == nil, "a plain drag")
        let correction = [0, 120, 240, 200, 230].map { CGPoint(x: $0, y: 0) }
        #expect(firing(correction) == nil, "an overshoot and its correction")
    }

    @Test func relatedWordsContinueTheBubble() {
        #expect(Vocabulary.related(to: "comer", excluding: []) == ["pão", "fruta", "biscoito"], "its own complements")
        #expect(Vocabulary.related(to: "Quero ir", excluding: []) == ["para casa", "ao banheiro", "à escola"])
        #expect(Vocabulary.related(to: "agora", excluding: []) == ["aqui", "ali", "perto"])
        let present = Set(Vocabulary.initial)
        #expect(Vocabulary.related(to: "querer", excluding: present) == ["dormir", "ouvir", "tomar banho"], "skips the words on screen")
        #expect(Vocabulary.related(to: "Quero ir e comer", excluding: []).count == 3, "even a weak result buds")
    }

    @Test func shakeBudsThreeWordsAndUndoRemovesThem() throws {
        let c = Composition()
        let original = c.chips
        let comer = try #require(c.chips.first { $0.text == "comer" })
        #expect(c.derive(from: comer.id))
        #expect(c.chips.map(\.text) == original.map(\.text) + ["pão", "fruta", "biscoito"])
        #expect(c.chips.contains(comer), "the shaken bubble stays")
        #expect(c.latestResult == nil, "a shake is not a fusion: the focus does not change")
        c.undo()
        #expect(c.chips == original)
        #expect(!c.canUndo)
    }

    @Test func aShakeAfterAFusionKeepsItsFocusAndDefersTheSplit() async throws {
        let c = Composition()
        c.tap(c.chips[0].id); c.tap(c.chips[1].id); c.tap(c.chips[0].id)
        await c.refresh()
        let result = try #require(c.chips.first { $0.text == "Quero ir" })
        #expect(c.derive(from: result.id))
        #expect(c.focus == result.id)
        #expect(c.splittable == nil, "a long press would undo the shake, not the fusion")
        c.undo(from: result.id)
        #expect(c.chips.count > 6, "the long press target is no longer the latest act")
        c.undo()
        #expect(c.splittable == result.id)
    }
}
