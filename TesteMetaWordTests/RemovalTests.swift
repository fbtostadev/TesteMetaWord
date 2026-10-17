import Testing
import Foundation
@testable import TesteMetaWord

@MainActor struct RemovalTests {
    @Test func aPhraseWritesItselfAgainWithoutTheWord() {
        let cases: [(phrase: String, index: Int, rest: String, word: String?)] = [
            ("Quero ir", 1, "Quero", "ir"),
            ("Quero ir", 0, "Ir", "querer"),
            ("Eu quero ir", 0, "Quero ir", "eu"),
            ("Quero ir agora", 1, "Quero agora", "ir"),
            ("Quero beber", 0, "Beber", "querer"),
            ("Quero ir, sim", 2, "Quero ir", "sim"),
            ("Quero comer e beber", 1, "Quero beber", "comer"),
            ("Quero comer e beber", 3, "Quero comer", "beber"),
            ("Quero comer e beber", 2, "Quero comer beber", nil),
            ("Quero ir para casa", 2, "Quero ir", "para casa"),
        ]
        for c in cases {
            let removal = Vocabulary.remove(c.index, from: c.phrase)
            #expect(removal == Vocabulary.Removal(rest: c.rest, word: c.word), "\(c.phrase) sem a palavra \(c.index)")
        }
    }

    @Test func aSingleWordHasNothingToGiveUp() {
        #expect(Vocabulary.remove(0, from: "Quero") == nil)
        #expect(Vocabulary.remove(0, from: "querer") == nil)
        #expect(Vocabulary.remove(5, from: "Quero ir") == nil)
        #expect(Vocabulary.remove(-1, from: "Quero ir") == nil)
    }

    @Test func theSubjectThatIsLeftConjugatesTheModal() {
        #expect(Vocabulary.remove(1, from: "Você quer ir")?.rest == "Você vai", "sem o modal, o verbo conjuga com o sujeito")
        #expect(Vocabulary.remove(0, from: "Você quer ir")?.rest == "Quero ir", "sem sujeito, a primeira pessoa")
    }

    @Test func theRestStillFusesByItsWords() {
        let rest = Vocabulary.remove(1, from: "Quero ir agora")?.rest
        #expect(rest == "Quero agora")
        #expect(Vocabulary.combine("ir", rest ?? "") != nil)
        #expect(Vocabulary.insert("ir", into: rest ?? "", at: 1)?.result == "Quero ir agora", "pôr de volta reproduz a frase")
    }

    @Test func theEngineReadsARemovalForEveryWordOfThePhrase() async throws {
        let (c, _) = try await InsertionTests.queroIr()
        #expect(c.lexicon.removals == [Vocabulary.Removal(rest: "Ir", word: "querer"), Vocabulary.Removal(rest: "Quero", word: "ir")])
        let single = RuleEngine.lexicon(for: Vocabulary.initial, focus: nil)
        #expect(single.removals == [nil], "uma palavra só não cede nada")
    }

    @Test func takingAWordOutIsAnActOfItsOwn() async throws {
        let (c, focus) = try await InsertionTests.queroIr()
        let before = c.chips
        let removed = try #require(c.removeWord(at: 1))
        let word = try #require(removed.word)

        let rest = try #require(c.chips.first { $0.id == focus.id })
        #expect(rest.text == "Quero", "a BubbleKey fica no lugar, com o resto da frase")
        #expect(rest.glassID == focus.glassID && rest.phase == focus.phase)
        #expect(rest.fusionCount == focus.fusionCount - 1)
        #expect(c.chips.first { $0.id == word }?.text == "ir")
        #expect(c.chips.count == before.count + 1, "as sugestões ficam")
        #expect(c.focus == focus.id, "o foco continua sendo a BubbleKey")
        #expect(c.canUndo)

        c.undo()
        #expect(c.chips == before, "o Undo devolve a palavra à frase")
    }

    @Test func theBubbleKeyReadsItsShorterPhraseOnceTheEngineAnswers() async throws {
        let (c, _) = try await InsertionTests.queroIr()
        _ = c.removeWord(at: 0)
        #expect(c.focusPhrase == nil, "a frase espera a leitura da nova BubbleKey")
        await c.refresh()
        #expect(c.focusPhrase == ["Ir"])
        #expect(c.removeWord(at: 0) == nil, "uma palavra só não cede nada")
    }

    @Test func removingAndPuttingTheWordBackElsewhereReorders() async throws {
        let (c, _) = try await InsertionTests.queroIr()
        let removed = try #require(c.removeWord(at: 1))
        let ir = try #require(removed.word)
        await c.refresh()
        let key = try #require(c.focus)
        c.tap(ir); c.tap(key)
        c.moveInsertion(by: -5)
        c.tap(key)
        #expect(c.chips.contains { $0.text == "Ir quero" }, "a ordem escolhida é final")
        c.undo()
        #expect(c.chips.contains { $0.text == "Quero" } && c.chips.contains { $0.text == "ir" })
        c.undo()
        #expect(c.chips.contains { $0.text == "Quero ir" })
        #expect(c.canUndo, "a fusão original continua no histórico")
    }

    @Test func aLongPressAfterARemovalRevertsIt() async throws {
        let (c, focus) = try await InsertionTests.queroIr()
        _ = c.removeWord(at: 1)
        let latest = try #require(c.latestResult)
        #expect(latest == focus.id)
        #expect(c.split(latest))
        #expect(c.chips.contains { $0.text == "Quero ir" } && !c.chips.contains { $0.text == "ir" })
    }
}
