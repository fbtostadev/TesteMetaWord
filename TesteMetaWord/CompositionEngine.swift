import Foundation

/// What gestures read synchronously. An engine produces it for one set of words.
struct Lexicon: Equatable {
    /// Known fusions among the words, keyed by the unordered pair of texts.
    var fusions: [Set<String>: Vocabulary.Combination] = [:]
    /// Optical center: the focus that was asked for, or the engine's pick when there was none.
    var focus: String?
    /// Atmosphere zone (1 inner … 3 outer) of every word except the focus.
    var zones: [String: Int] = [:]
    /// Words a shake buds from each word, none of them already present.
    var related: [String: [String]] = [:]
    /// Words of the focus's phrase, in order; the gaps between them are where another word enters.
    var phrase: [String] = []
    /// For every other word, the fusion of it entering the focus at each gap (0 … `phrase.count`).
    var insertions: [String: [Vocabulary.Combination]] = [:]
}

/// Source of combinations, suggestions, focus and zones, asked after every change of the word
/// set. Implementations may be slow (a local language model); gestures only see the last result.
protocol CompositionEngine: Sendable {
    func lexicon(for words: [String], focus: String?) async -> Lexicon
}

/// The predefined local rules of `Vocabulary`: instant, and the fallback for any other engine.
struct RuleEngine: CompositionEngine {
    func lexicon(for words: [String], focus: String?) async -> Lexicon {
        Self.lexicon(for: words, focus: focus)
    }

    static func lexicon(for words: [String], focus: String?) -> Lexicon {
        var fusions: [Set<String>: Vocabulary.Combination] = [:]
        for (i, a) in words.enumerated() {
            for b in words[(i + 1)...] {
                if let combination = Vocabulary.combine(a, b) { fusions[[a, b]] = combination }
            }
        }
        // Without a fusion, the word with the most strong fusions (the first on ties).
        func strong(_ word: String) -> Int { words.count { fusions[[word, $0]]?.strength == 1 } }
        let center = focus ?? words.max { strong($0) < strong($1) }
        let present = Set(words)
        let related = Dictionary(words.map { ($0, Vocabulary.related(to: $0, excluding: present)) }) { first, _ in first }
        guard let center else { return Lexicon(fusions: fusions, related: related) }
        let phrase = Vocabulary.words(of: center)
        let others = words.filter { $0 != center }
        let insertions = Dictionary(others.map { word in
            (word, (0...phrase.count).compactMap { Vocabulary.insert(word, into: center, at: $0) })
        }) { first, _ in first }
        // The zone is the strongest way the word can enter the focus.
        let zones = Dictionary(others.map { word in
            (word, insertions[word]?.map(\.strength).min() ?? Vocabulary.zone(of: word, focus: center))
        }) { first, _ in first }
        return Lexicon(fusions: fusions, focus: center, zones: zones, related: related, phrase: phrase, insertions: insertions)
    }
}
