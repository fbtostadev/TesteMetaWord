import Foundation

enum Vocabulary {
    struct Combination: Equatable {
        let result: String
        let suggestions: [String]
    }

    static let initial = ["querer", "ir", "comer", "beber", "eu", "brincar"]
    /// Fusion of two texts by the procedural grammar of `ml/vocabulary.json` (see `Grammar`).
    static func combine(_ a: String, _ b: String) -> Combination? {
        Grammar.shared.fuse(a, b)
    }

    /// Relevance of `word` to the composition's optical center, as an atmosphere zone:
    /// 1 combines with the focus, 2 combines with another present word, 3 has no combination.
    static func zone(of word: String, focus: String, among words: [String]) -> Int {
        if combine(word, focus) != nil { return 1 }
        if words.contains(where: { $0 != focus && combine(word, $0) != nil }) { return 2 }
        return 3
    }
}
