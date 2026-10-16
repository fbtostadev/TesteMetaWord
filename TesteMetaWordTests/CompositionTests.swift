import Testing
import Foundation
@testable import TesteMetaWord

@MainActor struct CompositionTests {
    @Test func vocabularyIsUnorderedAndRejectsUnknownPairs() {
        #expect(Vocabulary.combine("querer", "ir")?.result == "Quero ir")
        #expect(Vocabulary.combine("ir", "querer") == Vocabulary.combine("querer", "ir"))
        #expect(Vocabulary.combine("eu", "brincar") == nil)
        #expect(Vocabulary.combine("Quero ir", "agora")?.suggestions == ["perto", "longe"])
    }

    @Test func tapsRequireExplicitConfirmationAndUndoRestoresIdentity() {
        let c = Composition()
        let original = c.chips
        c.tap(original[0].id)
        c.tap(original[1].id)
        #expect(c.candidate != nil)
        #expect(c.chips == original)
        c.tap(original[0].id)
        #expect(c.chips.map(\.text).contains("Quero ir"))
        #expect(c.chips.map(\.text).contains("agora"))
        c.undo()
        #expect(c.chips == original)
        #expect(c.candidate == nil)
        #expect(!c.canUndo)
    }

    @Test func deepOverlapArmsImmediatelyAndReleaseReturnsThePair() {
        let c = Composition()
        let a = c.chips[0].id, b = c.chips[1].id
        c.beginDrag(a)
        c.updateProximity(target: b, penetration: 0.45, time: 0)
        #expect(c.dropCandidate == MergePair(source: a, target: b))
        #expect(c.candidate == nil)
        #expect(c.endDrag() == MergePair(source: a, target: b))
        #expect(c.candidate == MergePair(source: a, target: b))
        #expect(c.dragging == nil && c.dropCandidate == nil)
        #expect(!c.canUndo)
        c.tap(b)
        #expect(c.canUndo)
    }

    @Test func chainedUndoAndLongPressOnlyOnLatestResult() async throws {
        let c = Composition()
        func merge(_ a: String, _ b: String) async throws {
            let first = try #require(c.chips.first { $0.text == a })
            let second = try #require(c.chips.first { $0.text == b })
            c.tap(first.id); c.tap(second.id); c.tap(first.id)
            await c.refresh()
        }
        let initial = c.chips
        try await merge("querer", "ir")
        let intermediate = c.chips
        let older = try #require(c.chips.first { $0.text == "Quero ir" })
        try await merge("Quero ir", "agora")
        c.undo(from: older.id)
        #expect(c.chips != intermediate)
        let latest = try #require(c.chips.first { $0.text == "Quero ir agora" })
        c.undo(from: latest.id)
        #expect(c.chips == intermediate)
        c.undo()
        #expect(c.chips == initial)
    }

    @Test func invalidSelectionAndCancellationDoNotMutateComposition() {
        let c = Composition()
        let original = c.chips
        c.tap(original[2].id); c.tap(original[4].id)
        #expect(c.selected == original[4].id)
        #expect(c.candidate == nil)
        c.cancel()
        #expect(c.selected == nil)
        #expect(c.chips == original)
    }

    @Test func calibrationAndNewDragClearPendingCandidate() {
        let c = Composition()
        let a = c.chips[0].id, b = c.chips[1].id
        c.tap(a); c.tap(b)
        c.calibration.distance = 30
        #expect(c.candidate == nil)
        c.tap(a); c.tap(b)
        c.beginDrag(c.chips[2].id)
        #expect(c.candidate == nil)
        #expect(c.selected == nil)
    }

    @Test func existingSuggestionsAreNotDuplicated() async throws {
        let c = Composition()
        let a = c.chips[0].id, b = c.chips[1].id
        c.tap(a); c.tap(b); c.tap(a)
        await c.refresh()
        // The unchosen suggestion survives the chained merge exactly once.
        let result = try #require(c.chips.first { $0.text == "Quero ir" })
        let now = try #require(c.chips.first { $0.text == "agora" })
        c.tap(result.id); c.tap(now.id); c.tap(now.id)
        #expect(c.chips.filter { $0.text == "depois" }.count == 1)
        #expect(c.chips.filter { $0.text == "perto" }.count == 1)
    }

    @Test func shallowHoverNeverArmsAndMembraneResistsStalling() {
        let c = Composition()
        let a = c.chips[0].id, b = c.chips[1].id
        c.beginDrag(a)
        c.updateProximity(target: b, penetration: 0.1, time: 0)
        c.updateProximity(target: b, penetration: 0.1, time: 3)
        #expect(c.dropCandidate == nil)
        #expect(c.resistance == 1)
        c.updateProximity(target: b, penetration: 0.2, time: 3.1)
        #expect(c.resistance == 0)
    }

    @Test func retreatBelowThresholdDisarms() {
        let c = Composition()
        let a = c.chips[0].id, b = c.chips[1].id
        c.beginDrag(a)
        c.updateProximity(target: b, penetration: 0.5, time: 0)
        #expect(c.dropCandidate != nil)
        c.updateProximity(target: b, penetration: 0.3, time: 0.1)
        #expect(c.dropCandidate == nil)
        #expect(c.endDrag() == nil)
        #expect(c.candidate == nil)
        #expect(!c.canUndo)
    }

    @Test func fusionCarriesVisualIdentityAndAccumulatesSize() async throws {
        let c = Composition()
        let source = c.chips[0], target = c.chips[1]
        c.tap(source.id); c.tap(target.id); c.tap(source.id)
        await c.refresh()
        let result = try #require(c.chips.first { $0.text == "Quero ir" })
        #expect(result.fusionCount == 1)
        #expect(result.glassID == source.glassID)
        #expect(result.scale == 1.04)
        #expect(WordChip("frase longa", fusionCount: 20, phase: 0).scale == 1.24)
        let now = try #require(c.chips.first { $0.text == "agora" })
        c.tap(result.id); c.tap(now.id); c.tap(result.id)
        let phrase = try #require(c.chips.first { $0.text == "Quero ir agora" })
        #expect(phrase.fusionCount == 2)
        #expect(phrase.scale == 1.08)
        c.undo()
        #expect(c.chips.contains(result))
    }

    @Test func localGrammarSupportsSubjectAndDrinkComplements() {
        #expect(Vocabulary.combine("eu", "querer")?.result == "Eu quero")
        #expect(Vocabulary.combine("Eu quero", "brincar")?.result == "Eu quero brincar")
        #expect(Vocabulary.combine("água", "Quero beber")?.result == "Quero beber água")
        #expect(Vocabulary.combine("Quero beber água", "agora")?.result == "Quero beber água agora")
    }

    @Test func relevanceZonesFollowTheFocus() {
        #expect(Vocabulary.zone(of: "ir", focus: "querer", among: ["querer", "ir", "comer"]) == 1)
        #expect(Vocabulary.zone(of: "ir", focus: "comer", among: ["comer", "ir", "querer"]) == 2)
        #expect(Vocabulary.zone(of: "ir", focus: "comer", among: ["comer", "ir"]) == 3)
    }

    @Test func latestFusionBecomesTheOpticalCenterAndRezonesTheComposition() async throws {
        let c = Composition()
        let hub = try #require(c.chips.first { $0.text == "querer" })
        #expect(c.focus == hub.id, "before any fusion the word with most partners is the center")
        #expect(c.zones.values.allSatisfy { $0 == 1 })
        let ir = try #require(c.chips.first { $0.text == "ir" })
        c.tap(hub.id); c.tap(ir.id); c.tap(hub.id)
        await c.refresh()
        let result = try #require(c.chips.first { $0.text == "Quero ir" })
        #expect(c.focus == result.id)
        func zone(_ text: String) -> Int? { c.chips.first { $0.text == text }.flatMap { c.zones[$0.id] } }
        #expect(zone("agora") == 1 && zone("depois") == 1 && zone("eu") == 1)
        #expect(zone("comer") == 3 && zone("brincar") == 3)
        c.undo()
        await c.refresh()
        #expect(c.focus == hub.id)
    }

    @Test func familiesShareOrbitPhaseWithAFixedLag() throws {
        let c = Composition()
        let source = c.chips[0], target = c.chips[1]
        c.tap(source.id); c.tap(target.id); c.tap(source.id)
        let result = try #require(c.chips.first { $0.text == "Quero ir" })
        let now = try #require(c.chips.first { $0.text == "agora" })
        let later = try #require(c.chips.first { $0.text == "depois" })
        #expect(result.phase == source.phase)
        #expect(now.phase == result.phase + Physics.familyLag)
        #expect(later.phase == result.phase + 2 * Physics.familyLag)
        c.undo()
        #expect(c.chips.first { $0.id == target.id }?.phase == target.phase)
    }

    @Test func shallowOrInvalidDropDoesNotPrepareMerge() {
        let c = Composition()
        let a = c.chips[0].id, b = c.chips[1].id
        c.beginDrag(a)
        c.updateProximity(target: b, penetration: 0.44, time: 0)
        c.endDrag()
        #expect(c.candidate == nil)
        #expect(!c.canUndo)
        c.beginDrag(a)
        c.updateProximity(target: c.chips[4].id, penetration: 1, time: 0)
        c.updateProximity(target: nil, penetration: 0, time: 1)
        c.endDrag()
        #expect(c.candidate == nil)
    }

    @Test func gesturesFollowTheInjectedEngine() async {
        let c = Composition(engine: FixedEngine(lexicon: Lexicon(
            fusions: [["ir", "comer"]: Vocabulary.Combination(result: "Ir comer", suggestions: ["já", "logo"])],
            focus: "comer", zones: ["ir": 1, "querer": 3])))
        let ir = c.chips.first { $0.text == "ir" }!.id, comer = c.chips.first { $0.text == "comer" }!.id
        #expect(!c.compatible(ir, comer), "rules know nothing about ir + comer")
        await c.refresh()
        #expect(c.compatible(ir, comer))
        #expect(c.focus == comer)
        #expect(c.zones[ir] == 1)
        #expect(c.zones[c.chips.first { $0.text == "eu" }!.id] == 2, "unranked words wait in the middle zone")
        c.tap(ir); c.tap(comer); c.tap(ir)
        #expect(c.chips.map(\.text).contains("Ir comer"))
        #expect(c.chips.map(\.text).contains("logo"))
    }

    @Test func lexiconForOutdatedWordsIsDropped() async {
        let c = Composition(engine: FixedEngine(lexicon: Lexicon(focus: "eu"), delay: .milliseconds(50)))
        let pending = Task { await c.refresh() }
        await Task.yield()
        let a = c.chips[0].id, b = c.chips[1].id
        c.tap(a); c.tap(b); c.tap(a)
        await pending.value
        #expect(c.lexicon.focus == "querer", "the words changed while the engine was thinking")
    }
}

/// Engine stub: always answers the same lexicon, optionally after a delay.
private struct FixedEngine: CompositionEngine {
    let lexicon: Lexicon
    var delay: Duration = .zero
    func lexicon(for words: [String], focus: String?) async -> Lexicon {
        try? await Task.sleep(for: delay)
        return lexicon
    }
}
