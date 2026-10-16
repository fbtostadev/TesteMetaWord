import Foundation

enum Vocabulary {
    struct Combination: Equatable {
        let result: String
        let suggestions: [String]
    }

    static let initial = ["querer", "ir", "comer", "beber", "eu", "brincar"]
    private static let rules: [(Set<String>, Combination)] = {
        var entries: [(Set<String>, Combination)] = [
        (["querer", "ir"], Combination(result: "Quero ir", suggestions: ["agora", "depois"])),
        (["querer", "comer"], Combination(result: "Quero comer", suggestions: ["mais", "menos"])),
        (["querer", "beber"], Combination(result: "Quero beber", suggestions: ["água", "suco"])),
        (["Quero ir", "agora"], Combination(result: "Quero ir agora", suggestions: ["perto", "longe"])),
        (["Quero ir", "depois"], Combination(result: "Quero ir depois", suggestions: ["hoje", "amanhã"]))
        ]
        entries.append((["eu", "querer"], Combination(result: "Eu quero", suggestions: ["ir", "brincar"])))
        entries.append((["querer", "brincar"], Combination(result: "Quero brincar", suggestions: ["agora", "depois"])))
        for verb in ["ir", "comer", "beber", "brincar"] {
            let suggestions = verb == "beber" ? ["água", "suco"] : ["agora", "depois"]
            entries.append((["Eu quero", verb], Combination(result: "Eu quero " + verb, suggestions: suggestions)))
            entries.append((["eu", "Quero " + verb], Combination(result: "Eu quero " + verb, suggestions: suggestions)))
        }
        for prefix in ["Quero beber", "Eu quero beber"] {
            for drink in ["água", "suco"] {
                entries.append(([prefix, drink], Combination(result: prefix + " " + drink, suggestions: ["agora", "depois"])))
            }
        }
        let phrases = ["Quero comer", "Quero beber", "Quero brincar", "Eu quero ir", "Eu quero comer", "Eu quero beber", "Eu quero brincar", "Quero beber água", "Quero beber suco", "Eu quero beber água", "Eu quero beber suco"]
        for phrase in phrases {
            for time in ["agora", "depois"] {
                entries.append(([phrase, time], Combination(result: phrase + " " + time, suggestions: ["aqui", "ali"])))
            }
        }
        return entries
    }()

    static func combine(_ a: String, _ b: String) -> Combination? {
        guard a != b else { return nil }
        return rules.first { $0.0 == Set([a, b]) }?.1
    }

    /// Relevance of `word` to the composition's optical center, as an atmosphere zone:
    /// 1 combines with the focus, 2 combines with another present word, 3 has no combination.
    static func zone(of word: String, focus: String, among words: [String]) -> Int {
        if combine(word, focus) != nil { return 1 }
        if words.contains(where: { $0 != focus && combine(word, $0) != nil }) { return 2 }
        return 3
    }
}
