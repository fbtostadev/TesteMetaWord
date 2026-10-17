import Foundation

enum Vocabulary {
    struct Combination: Equatable {
        let result: String
        let suggestions: [String]
        /// 1 strong (a full phrase), 2 medium (telegraphic or repaired), 3 weak (coordinated).
        var strength = 1
    }

    /// A phrase after one of its words is taken out: what is left, and the word as a bubble of its
    /// own (nil when nothing comes out, as with the coordinating "e").
    struct Removal: Equatable {
        let rest: String
        let word: String?
    }

    static let initial = ["querer", "ir", "comer", "beber", "eu", "brincar"]
    /// Fusion of two texts by the procedural grammar of `ml/vocabulary.json` (see `Grammar`).
    static func combine(_ a: String, _ b: String) -> Combination? {
        Grammar.shared.fuse(a, b)
    }

    /// The words of a phrase, each one a vocabulary word ("Quero", "ir", "para casa").
    static func words(of text: String) -> [String] {
        Grammar.shared.units(of: text).map(\.text)
    }

    /// `text` entering `phrase` before its word `index`, in that order (see `Grammar.insert`).
    static func insert(_ text: String, into phrase: String, at index: Int) -> Combination? {
        Grammar.shared.insert(text, into: phrase, at: index)
    }

    /// `phrase` without its word `index` (see `Grammar.remove`).
    static func remove(_ index: Int, from phrase: String) -> Removal? {
        Grammar.shared.remove(index, from: phrase)
    }

    /// Up to three words related to `text`, budded by a shake (see `Grammar.related`).
    static func related(to text: String, excluding present: Set<String>) -> [String] {
        Grammar.shared.related(to: text, excluding: present)
    }

    /// Relevance of `word` to the composition's optical center, as an atmosphere zone: the
    /// strength of their fusion (every pair fuses; farther zones fuse more loosely).
    static func zone(of word: String, focus: String) -> Int {
        combine(word, focus)?.strength ?? 3
    }
}
