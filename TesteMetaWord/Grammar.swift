import Foundation

/// Procedural composition grammar read from `ml/vocabulary.json`, the same file that builds the
/// model's dataset (`ml/build_dataset.py`, class `Grammar`). A phrase is a frame of slots,
/// [subject] [não] modal verb [complement | quantity] [time]; a word fills one slot. Two texts
/// fuse when at least one is a single word, their slots do not collide and the merged frame is
/// a valid phrase. Suggestions are fillers for what the merged frame still lacks.
struct Grammar: Sendable {
    enum Slot: Int, CaseIterable { case subject, negation, modal, verb, tail, time }

    /// One value per slot; `nil` is empty.
    typealias Frame = [String?]

    private let spec: Spec
    /// Slot each single word fills. Extra words fill none: they never fuse.
    private let slotOf: [String: Slot]
    /// Single words, including the extra ones.
    let atoms: Set<String>
    /// Every valid phrase by its rendered text.
    private var phrases: [String: Frame] = [:]

    static let shared: Grammar = {
        guard let url = Bundle.main.url(forResource: "vocabulary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let grammar = try? Grammar(json: data)
        else { fatalError("vocabulary.json missing from the app bundle or malformed") }
        return grammar
    }()

    init(json data: Data) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        spec = try decoder.decode(Spec.self, from: data)
        var slotOf: [String: Slot] = [:]
        for subject in spec.subjects.keys { slotOf[subject] = .subject }
        slotOf[spec.negation] = .negation
        for modal in spec.modals { slotOf[modal] = .modal }
        for (verb, verbSpec) in spec.verbs {
            slotOf[verb] = .verb
            for complement in verbSpec.complements { slotOf[complement] = .tail }
        }
        for quantity in spec.quantities { slotOf[quantity] = .tail }
        for time in spec.times { slotOf[time] = .time }
        self.slotOf = slotOf
        atoms = Set(slotOf.keys).union(spec.extraWords)
        phrases = Dictionary(frames().map { (render($0), $0) }) { first, _ in first }
    }

    func fuse(_ a: String, _ b: String) -> Vocabulary.Combination? {
        guard a != b, atoms.contains(a) || atoms.contains(b),
              let first = frame(of: a), let second = frame(of: b),
              !zip(first, second).contains(where: { $0 != nil && $1 != nil })
        else { return nil }
        let merged = zip(first, second).map { $0 ?? $1 }
        guard isValid(merged) else { return nil }
        return Vocabulary.Combination(result: render(merged), suggestions: suggestions(for: merged))
    }

    /// A phrase's frame, or a one-slot frame for a word.
    private func frame(of text: String) -> Frame? {
        if let phrase = phrases[text] { return phrase }
        guard let slot = slotOf[text] else { return nil }
        var frame = Frame(repeating: nil, count: Slot.allCases.count)
        frame[slot.rawValue] = text
        return frame
    }

    /// Every valid phrase: an optional subject and negation, a modal, then optionally a verb with
    /// its complement or quantity and a time.
    private func frames() -> [Frame] {
        var frames: [Frame] = []
        for subject in [nil] + spec.subjects.keys.map(Optional.some) {
            for negation in [nil, spec.negation] {
                for modal in spec.modals {
                    frames.append([subject, negation, modal, nil, nil, nil])
                    for (verb, verbSpec) in spec.verbs {
                        let tails = [nil] + (verbSpec.complements + (verbSpec.quantity ? spec.quantities : [])).map(Optional.some)
                        for tail in tails {
                            for time in [nil] + spec.times.map(Optional.some) {
                                frames.append([subject, negation, modal, verb, tail, time])
                            }
                        }
                    }
                }
            }
        }
        return frames
    }

    private func isValid(_ frame: Frame) -> Bool {
        guard frame[Slot.modal.rawValue] != nil, frame.count(where: { $0 != nil }) >= 2 else { return false }
        let tail = frame[Slot.tail.rawValue]
        guard let verb = frame[Slot.verb.rawValue] else { return tail == nil && frame[Slot.time.rawValue] == nil }
        guard let tail, let verbSpec = spec.verbs[verb] else { return true }
        return verbSpec.complements.contains(tail) || (verbSpec.quantity && spec.quantities.contains(tail))
    }

    /// Without a subject the phrase is in the first person; only an explicit subject is written.
    private func render(_ frame: Frame) -> String {
        let subject = frame[Slot.subject.rawValue]
        let person = spec.subjects[subject ?? spec.defaultSubject] ?? [:]
        var words: [String] = []
        if subject != nil, let label = person["label"] { words.append(label) }
        if let negation = frame[Slot.negation.rawValue] { words.append(negation) }
        if let modal = frame[Slot.modal.rawValue] { words.append(person[modal] ?? modal) }
        words += [Slot.verb, .tail, .time].compactMap { frame[$0.rawValue] }
        let text = words.joined(separator: " ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private func suggestions(for frame: Frame) -> [String] {
        let verb = frame[Slot.verb.rawValue]
        if let time = frame[Slot.time.rawValue] {
            return verb.flatMap { spec.afterTimeSuggest.byVerb[$0]?[time] } ?? spec.afterTimeSuggest.fallback
        }
        if frame[Slot.tail.rawValue] != nil { return spec.afterComplementSuggest }
        if let verb { return spec.verbs[verb]?.suggest ?? [] }
        if frame[Slot.negation.rawValue] != nil { return spec.negatedModalSuggest }
        return spec.subjectModalSuggest
    }
}

private extension Grammar {
    struct Spec: Decodable, Sendable {
        struct Verb: Decodable, Sendable {
            let complements: [String]
            let quantity: Bool
            let suggest: [String]

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                complements = try c.decode([String].self, forKey: .complements)
                quantity = try c.decodeIfPresent(Bool.self, forKey: .quantity) ?? false
                suggest = try c.decode([String].self, forKey: .suggest)
            }

            private enum CodingKeys: String, CodingKey { case complements, quantity, suggest }
        }

        /// `{"default": [a, b], "<verb>": {"<time>": [a, b]}}`.
        struct AfterTime: Decodable, Sendable {
            let fallback: [String]
            let byVerb: [String: [String: [String]]]

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: AnyKey.self)
                var fallback: [String] = []
                var byVerb: [String: [String: [String]]] = [:]
                for key in c.allKeys {
                    if key.stringValue == "default" {
                        fallback = try c.decode([String].self, forKey: key)
                    } else {
                        byVerb[key.stringValue] = try c.decode([String: [String]].self, forKey: key)
                    }
                }
                self.fallback = fallback
                self.byVerb = byVerb
            }
        }

        /// Subject → its "label" and the conjugation of each modal.
        let subjects: [String: [String: String]]
        let defaultSubject: String
        let modals: [String]
        let negation: String
        let verbs: [String: Verb]
        let subjectModalSuggest: [String]
        let negatedModalSuggest: [String]
        let quantities: [String]
        let times: [String]
        let afterComplementSuggest: [String]
        let afterTimeSuggest: AfterTime
        let extraWords: [String]
    }

    struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
