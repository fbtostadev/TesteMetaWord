import Testing
@testable import TesteMetaWord

struct GrammarTests {
    /// The hand-written rule table the grammar replaced (Vocabulary.swift before
    /// exp/gramatica-procedural), as (a, b, result, suggestions).
    static let legacyRules: [(String, String, String, [String])] = {
        var rules: [(String, String, String, [String])] = [
            ("querer", "ir", "Quero ir", ["agora", "depois"]),
            ("querer", "comer", "Quero comer", ["mais", "menos"]),
            ("querer", "beber", "Quero beber", ["água", "suco"]),
            ("Quero ir", "agora", "Quero ir agora", ["perto", "longe"]),
            ("Quero ir", "depois", "Quero ir depois", ["hoje", "amanhã"]),
            ("eu", "querer", "Eu quero", ["ir", "brincar"]),
            ("querer", "brincar", "Quero brincar", ["agora", "depois"])
        ]
        for verb in ["ir", "comer", "beber", "brincar"] {
            let suggestions = verb == "beber" ? ["água", "suco"] : ["agora", "depois"]
            rules.append(("Eu quero", verb, "Eu quero " + verb, suggestions))
            rules.append(("eu", "Quero " + verb, "Eu quero " + verb, suggestions))
        }
        for prefix in ["Quero beber", "Eu quero beber"] {
            for drink in ["água", "suco"] {
                rules.append((prefix, drink, prefix + " " + drink, ["agora", "depois"]))
            }
        }
        let phrases = ["Quero comer", "Quero beber", "Quero brincar", "Eu quero ir", "Eu quero comer", "Eu quero beber", "Eu quero brincar", "Quero beber água", "Quero beber suco", "Eu quero beber água", "Eu quero beber suco"]
        for phrase in phrases {
            for time in ["agora", "depois"] {
                rules.append((phrase, time, phrase + " " + time, ["aqui", "ali"]))
            }
        }
        return rules
    }()

    /// Where the grammar deliberately differs from the old table: the suggestions follow the
    /// verb and the time, with or without a subject, as they already did without one.
    static let changedSuggestions: [Set<String>: [String]] = [
        ["Eu quero", "comer"]: ["mais", "menos"],
        ["eu", "Quero comer"]: ["mais", "menos"],
        ["Eu quero ir", "agora"]: ["perto", "longe"],
        ["Eu quero ir", "depois"]: ["hoje", "amanhã"]
    ]

    @Test func grammarKeepsEveryLegacyFusion() {
        for (a, b, result, suggestions) in Self.legacyRules {
            let expected = Self.changedSuggestions[[a, b]] ?? suggestions
            #expect(Vocabulary.combine(a, b) == Vocabulary.Combination(result: result, suggestions: expected), "\(a) + \(b)")
            #expect(Vocabulary.combine(b, a) == Vocabulary.combine(a, b))
        }
    }

    @Test func initialWordsCombineExactlyAsBefore() {
        let words = Vocabulary.initial
        for (i, a) in words.enumerated() {
            for b in words[(i + 1)...] {
                let legacy = Self.legacyRules.contains { Set([$0.0, $0.1]) == Set([a, b]) }
                #expect((Vocabulary.combine(a, b) != nil) == legacy, "\(a) + \(b)")
            }
        }
    }

    @Test func grammarComposesBeyondTheOldTable() {
        #expect(Vocabulary.combine("não", "querer")?.result == "Não quero")
        #expect(Vocabulary.combine("você", "poder")?.result == "Você pode")
        #expect(Vocabulary.combine("Você pode", "dormir")?.result == "Você pode dormir")
        #expect(Vocabulary.combine("nós", "Não preciso")?.result == "Nós não precisamos")
        #expect(Vocabulary.combine("gostar", "ver")?.result == "Gosto de ver")
        #expect(Vocabulary.combine("Gosto de ver", "TV")?.suggestions == ["agora", "depois"])
        #expect(Vocabulary.combine("Quero ir", "ao parque")?.result == "Quero ir ao parque")
        #expect(Vocabulary.combine("Quero tomar banho", "amanhã")?.result == "Quero tomar banho amanhã")
    }

    @Test func grammarRejectsCollidingOrIncompleteFrames() {
        #expect(Vocabulary.combine("eu", "brincar") == nil, "no modal")
        #expect(Vocabulary.combine("querer", "agora") == nil, "time without a verb")
        #expect(Vocabulary.combine("Quero beber", "pão") == nil, "complement of another verb")
        #expect(Vocabulary.combine("Quero ir", "mais") == nil, "ir takes no quantity")
        #expect(Vocabulary.combine("Quero ir agora", "depois") == nil, "two times")
        #expect(Vocabulary.combine("Eu quero", "você") == nil, "two subjects")
        #expect(Vocabulary.combine("Quero ir", "Quero comer") == nil, "two phrases")
        #expect(Vocabulary.combine("aqui", "Quero ir") == nil, "extra words fill no slot")
        #expect(Vocabulary.combine("querer", "querer") == nil)
    }

    @Test func everySuggestionIsAKnownWord() {
        let grammar = Grammar.shared
        for (a, b, _, _) in Self.legacyRules {
            for word in Vocabulary.combine(a, b)?.suggestions ?? [] {
                #expect(grammar.atoms.contains(word), "\(word) after \(a) + \(b)")
            }
        }
    }
}
