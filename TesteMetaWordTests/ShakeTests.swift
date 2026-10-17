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

    @Test func theKeyStillSplitsAfterAShake() async throws {
        let c = Composition()
        c.tap(c.chips[0].id); c.tap(c.chips[1].id); c.tap(c.chips[0].id)
        await c.refresh()
        let result = try #require(c.chips.first { $0.text == "Quero ir" })
        let comer = try #require(c.chips.first { $0.text == "comer" })
        #expect(c.derive(from: comer.id))
        #expect(c.focus == result.id, "a shake keeps the focus")
        #expect(c.splittable == result.id, "and the key can still split")
        let shaken = c.chips
        #expect(c.split(result.id))
        let texts = c.chips.map(\.text)
        #expect(texts.contains("querer") && texts.contains("ir"), "the origins come back")
        #expect(!texts.contains("Quero ir") && !texts.contains("agora") && !texts.contains("depois"), "with its suggestions gone")
        #expect(texts.contains("pão") && texts.contains("fruta") && texts.contains("biscoito"), "later words stay")
        #expect(c.latestResult == nil)
        c.undo()
        #expect(c.chips == shaken, "Undo reverts the split alone")
    }

    @Test func aSplitTwinFusesPassivelyIntoTheWordAlreadyThere() async throws {
        // An engine whose shake of "eu" buds "ir": after querer + ir, splitting the key brings a
        // second "ir" back.
        let c = Composition(engine: BuddingEngine(related: ["eu": ["ir"]]))
        let querer = try #require(c.chips.first { $0.text == "querer" })
        let ir = try #require(c.chips.first { $0.text == "ir" })
        c.tap(querer.id); c.tap(ir.id); c.tap(querer.id)
        await c.refresh()
        let key = try #require(c.chips.first { $0.text == "Quero ir" })
        let eu = try #require(c.chips.first { $0.text == "eu" })
        #expect(c.derive(from: eu.id))
        let twin = try #require(c.chips.first { $0.text == "ir" })
        #expect(c.split(key.id))
        #expect(c.chips.count { $0.text == "ir" } == 2)
        #expect(c.duplicates.map(\.keeper) == [twin.id], "the word already there keeps its place")
        c.absorbDuplicates()
        #expect(c.chips.count { $0.text == "ir" } == 1)
        #expect(c.duplicates.isEmpty)
        c.undo()
        #expect(c.chips.contains { $0.id == key.id }, "one Undo reverts the split and its passive fusion")
    }
}

/// The local rules, with chosen words budded by a shake.
private struct BuddingEngine: CompositionEngine {
    let related: [String: [String]]
    func lexicon(for words: [String], focus: String?) async -> Lexicon {
        var lexicon = RuleEngine.lexicon(for: words, focus: focus)
        lexicon.related.merge(related) { _, chosen in chosen }
        return lexicon
    }
}
