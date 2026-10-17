import Foundation

enum Vocabulary {
    struct Combination: Equatable {
        let result: String
        let suggestions: [String]
        /// 1 strong (a full phrase), 2 medium (telegraphic or repaired), 3 weak (coordinated).
        var strength = 1
    }

    static let initial = ["querer", "ir", "comer", "beber", "eu", "brincar"]
    /// Fusion of two texts by the procedural grammar of `ml/vocabulary.json` (see `Grammar`).
    static func combine(_ a: String, _ b: String) -> Combination? {
        Grammar.shared.fuse(a, b)
    }

    /// Relevance of `word` to the composition's optical center, as an atmosphere zone: the
    /// strength of their fusion (every pair fuses; farther zones fuse more loosely).
    static func zone(of word: String, focus: String) -> Int {
        combine(word, focus)?.strength ?? 3
    }
}
