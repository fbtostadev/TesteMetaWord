import Testing
import Foundation
@testable import TesteMetaWord

@MainActor struct InsertionTests {
    /// querer + ir by taps, with the engine's answer applied: the BubbleKey is "Quero ir".
    static func queroIr() async throws -> (Composition, WordChip) {
        let c = Composition()
        let querer = try #require(c.chips.first { $0.text == "querer" })
        let ir = try #require(c.chips.first { $0.text == "ir" })
        c.tap(querer.id); c.tap(ir.id); c.tap(querer.id)
        #expect(c.focusPhrase == nil, "the phrase waits for the engine to read the new BubbleKey")
        await c.refresh()
        let focus = try #require(c.chips.first { $0.text == "Quero ir" })
        #expect(c.focusPhrase == ["Quero", "ir"])
        return (c, focus)
    }

    @Test func theGapUnderTheFingerChoosesWhereTheWordEnters() async throws {
        for (gap, result) in [(0, "Eu quero ir"), (1, "Quero eu ir"), (2, "Quero ir eu")] {
            let (c, focus) = try await Self.queroIr()
            let eu = try #require(c.chips.first { $0.text == "eu" })
            c.beginDrag(eu.id)
            c.updateProximity(target: focus.id, penetration: 0.5, time: 0)
            #expect(!c.choosingGap)
            c.updateInsertion(gap)
            #expect(c.insertion == gap)
            #expect(c.choosingGap, "over the BubbleKey the gap takes priority over a shake")
            let pair = try #require(c.endDrag())
            #expect(c.insertion == gap, "the release keeps the gap for the convergence")
            c.tap(pair.source)
            #expect(c.chips.contains { $0.text == result }, "gap \(gap)")
        }
    }

    @Test func aReleaseWithoutAGapEntersWhereTheGrammarReadsBest() async throws {
        let (c, focus) = try await Self.queroIr()
        let eu = try #require(c.chips.first { $0.text == "eu" })
        c.beginDrag(eu.id)
        c.updateProximity(target: focus.id, penetration: 0.5, time: 0)
        let pair = try #require(c.endDrag())
        #expect(c.insertion == 0)
        c.tap(pair.source)
        #expect(c.chips.contains { $0.text == "Eu quero ir" })
    }

    @Test func tapsStartAtTheNaturalGapAndStepThroughTheOthers() async throws {
        let (c, focus) = try await Self.queroIr()
        let agora = try #require(c.chips.first { $0.text == "agora" })
        c.tap(agora.id); c.tap(focus.id)
        #expect(c.insertion == 2, "agora reads best at the end")
        c.moveInsertion(by: -1)
        #expect(c.insertion == 1)
        c.moveInsertion(by: -5)
        #expect(c.insertion == 0, "stops at the start")
        c.moveInsertion(by: 1)
        c.tap(focus.id)
        let result = try #require(c.chips.first { $0.text == "Quero agora ir" })
        #expect(c.focus == result.id)
        await c.refresh()
        #expect(c.focusPhrase == ["Quero", "agora", "ir"])
    }

    @Test func pairsWithoutTheBubbleKeyFuseAsAWhole() async throws {
        let (c, _) = try await Self.queroIr()
        let comer = try #require(c.chips.first { $0.text == "comer" })
        let agora = try #require(c.chips.first { $0.text == "agora" })
        c.beginDrag(comer.id)
        c.updateProximity(target: agora.id, penetration: 0.5, time: 0)
        c.updateInsertion(0)
        #expect(c.insertion == nil)
        c.endDrag()
        #expect(c.insertion == nil)
        c.tap(comer.id)
        #expect(c.chips.contains { $0.text == "Comer agora" })
    }

    @Test func zonesFollowTheStrongestGap() async throws {
        let (c, _) = try await Self.queroIr()
        let eu = try #require(c.chips.first { $0.text == "eu" })
        let comer = try #require(c.chips.first { $0.text == "comer" })
        #expect(c.zones[eu.id] == 1)
        #expect(c.zones[comer.id] == 3)
    }
}
