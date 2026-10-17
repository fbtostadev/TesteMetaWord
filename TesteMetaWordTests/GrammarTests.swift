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

    @Test func initialWordsFuseStronglyExactlyAsBeforeAndLooselyOtherwise() {
        let words = Vocabulary.initial
        for (i, a) in words.enumerated() {
            for b in words[(i + 1)...] {
                let legacy = Self.legacyRules.contains { Set([$0.0, $0.1]) == Set([a, b]) }
                let strength = Vocabulary.combine(a, b)?.strength
                #expect(strength != nil, "\(a) + \(b) must fuse")
                #expect((strength == 1) == legacy, "\(a) + \(b)")
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
        #expect(Vocabulary.combine("Eu quero", "Você pode")?.strength == 3, "two subjects collide")
    }

    /// Slots that fit outside the phrase grammar: telegraphic or repaired, zone 2.
    @Test func fittingSlotsFuseWithMediumStrength() {
        let cases: [(String, String, String)] = [
            ("eu", "brincar", "Eu brinco"),
            ("você", "dormir", "Você dorme"),
            ("querer", "agora", "Quero agora"),
            ("gostar", "água", "Gosto de água"),
            ("Quero beber", "pão", "Quero beber pão"),
            ("Quero ir", "mais", "Quero ir mais"),
            ("Quero ir", "longe", "Quero ir longe"),
            ("dor", "aqui", "Dor, aqui"),
            ("sim", "Quero ir", "Sim, quero ir"),
            ("comer", "agora", "Comer agora")
        ]
        for (a, b, result) in cases {
            let fused = Vocabulary.combine(a, b)
            #expect(fused?.result == result, "\(a) + \(b)")
            #expect(fused?.strength == 2, "\(a) + \(b)")
        }
    }

    /// Colliding slots, two phrases or an earlier weak result: coordinated, zone 3.
    @Test func collidingSlotsFuseWeaklyByCoordination() {
        let cases: [(String, String, String)] = [
            ("Quero comer", "beber", "Quero comer e beber"),
            ("Quero ir agora", "depois", "Quero ir agora e depois"),
            ("Quero ir", "Quero comer", "Quero comer e quero ir"),
            ("comer", "ir", "Comer e ir"),
            ("obrigado", "sim", "Obrigado, sim")
        ]
        for (a, b, result) in cases {
            let fused = Vocabulary.combine(a, b)
            #expect(fused?.result == result, "\(a) + \(b)")
            #expect(fused?.strength == 3, "\(a) + \(b)")
        }
        #expect(Vocabulary.combine("Quero comer e beber", "agora")?.result == "Quero comer e beber agora")
        #expect(Vocabulary.combine("Quero comer", "beber")?.suggestions == ["mais", "menos"], "the leading phrase suggests")
        #expect(Vocabulary.combine("querer", "querer") == nil)
    }

    @Test func mediumResultsKeepFusingByTheirSlots() {
        let telegraphic = Vocabulary.combine("comer", "agora")?.result
        #expect(telegraphic == "Comer agora")
        let full = Vocabulary.combine("Eu quero", telegraphic ?? "")
        #expect(full?.result == "Eu quero comer agora")
        #expect(full?.strength == 1)
    }

    @Test func everySuggestionIsAKnownWord() {
        let grammar = Grammar.shared
        for (a, b, _, _) in Self.legacyRules {
            for word in Vocabulary.combine(a, b)?.suggestions ?? [] {
                #expect(grammar.atoms.contains(word), "\(word) after \(a) + \(b)")
            }
        }
    }

    @Test func phrasesSplitIntoVocabularyWords() {
        #expect(Vocabulary.words(of: "Gosto de brincar de massinha") == ["Gosto de", "brincar", "de massinha"])
        #expect(Vocabulary.words(of: "Sim, quero ir") == ["Sim,", "quero", "ir"])
        #expect(Vocabulary.words(of: "Nós tomamos banho") == ["Nós", "tomamos banho"])
        #expect(Vocabulary.words(of: "Quero comer e beber") == ["Quero", "comer", "e", "beber"])
    }

    /// The person chooses the order; the grammar only conjugates, and grades the order.
    @Test func insertionKeepsTheChosenOrder() {
        #expect(Vocabulary.insert("agora", into: "Quero ir", at: 2) == Vocabulary.combine("Quero ir", "agora"))
        let chosen = Vocabulary.insert("agora", into: "Quero ir", at: 1)
        #expect(chosen?.result == "Quero agora ir")
        #expect(chosen?.strength == 2, "out of the natural order, one step weaker")
        let cases: [(String, String, Int, String, Int)] = [
            ("eu", "Quero ir", 0, "Eu quero ir", 1),
            ("eu", "Quero ir", 2, "Quero ir eu", 2),
            ("você", "Quero ir", 0, "Você quer ir", 1),
            ("você", "Quero ir", 1, "Quer você ir", 2),
            ("querer", "Eu brinco", 1, "Eu quero brincar", 1),
            ("sim", "Quero ir", 2, "Quero ir, sim", 3),
            ("eu", "brincar", 1, "Brinco eu", 3),
            ("Quero ir", "eu", 1, "Eu quero ir", 1)
        ]
        for (text, phrase, index, result, strength) in cases {
            let inserted = Vocabulary.insert(text, into: phrase, at: index)
            #expect(inserted?.result == result, "\(text) → \(phrase) @\(index)")
            #expect(inserted?.strength == strength, "\(text) → \(phrase) @\(index)")
        }
        #expect(Vocabulary.insert("ir", into: "ir", at: 0) == nil)
    }

    @Test func twinSlotsMeetWithE() {
        let cases: [(String, String, Int, String)] = [
            ("comer", "Quero ir", 2, "Quero ir e comer"),
            ("comer", "Quero ir", 0, "Comer e quero ir"),
            ("comer", "Quero ir", 1, "Quero comer e ir"),
            ("agora", "Quero comer e beber", 4, "Quero comer e beber agora")
        ]
        for (text, phrase, index, result) in cases {
            let inserted = Vocabulary.insert(text, into: phrase, at: index)
            #expect(inserted?.result == result, "\(text) → \(phrase) @\(index)")
            #expect(inserted?.strength == 3)
        }
        #expect(Vocabulary.insert("beber", into: "Quero comer", at: 2) == Vocabulary.combine("Quero comer", "beber"))
    }

    /// Wherever the grammar's own order is reachable, some gap gives exactly the fusion.
    @Test func someGapGivesEachLegacyFusion() {
        for (a, b, _, _) in Self.legacyRules {
            let fused = Vocabulary.combine(a, b)
            let gaps = (0...Vocabulary.words(of: a).count).compactMap { Vocabulary.insert(b, into: a, at: $0) }
            #expect(gaps.contains(fused!), "\(b) → \(a)")
            #expect(gaps.map(\.strength).min() == fused?.strength)
        }
    }
}
