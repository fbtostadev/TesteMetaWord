import Foundation
import Synchronization

/// Procedural composition grammar read from `ml/vocabulary.json`, the same file that builds the
/// model's dataset (`ml/build_dataset.py`, class `Grammar`). A phrase is a frame of slots,
/// [interjection,] [subject] [não] [modal] [verb] [complement | quantity] [time] [place]; a word
/// fills one slot. Any two different texts fuse, with a strength that becomes the atmosphere zone:
/// 1. strong: the merged frame is a phrase of the dataset's grammar ("Quero ir");
/// 2. medium: the slots fit but the phrase is telegraphic or repaired ("Eu brinco", "Dor, aqui");
/// 3. weak: the slots collide or a text is unknown, so the two are coordinated ("Quero comer e beber").
/// Suggestions are fillers for what the merged frame still lacks.
struct Grammar: Sendable {
    enum Slot: Int, CaseIterable { case interjection, subject, negation, modal, verb, tail, time, place }

    /// One value per slot; `nil` is empty.
    typealias Frame = [String?]

    /// A word of a phrase as written (`text`, with its comma), the slot it fills and its
    /// dictionary form. `slot` is nil for the coordinating "e" and for words the grammar does not know.
    struct Unit: Equatable, Sendable {
        let text: String
        let slot: Slot?
        let lemma: String
    }

    private let spec: Spec
    /// Slot each single word fills.
    private let slotOf: [String: Slot]
    /// Single words.
    let atoms: Set<String>
    /// Every word with its slot, in slot order and then in the order of the vocabulary file.
    private let ranked: [(word: String, slot: Slot)]
    /// Every strong phrase by its rendered text.
    private var phrases: [String: Frame] = [:]
    /// Medium results rendered so far, so they keep fusing by their slots.
    private let rendered = FrameCache()
    /// Every written form of a word, lowercased, with its slot and dictionary form: subjects,
    /// conjugated modals and verbs, complements and the rest ("gosto de", "tomamos banho", "e").
    private let forms: [String: Form]
    /// Most spaces in a written form, plus one.
    private let longestForm: Int

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
        for place in spec.places { slotOf[place] = .place }
        for interjection in spec.interjections { slotOf[interjection] = .interjection }
        self.slotOf = slotOf
        atoms = Set(slotOf.keys).union(spec.extraWords)
        let verbSpecs = spec.verbs
        let verbs = verbSpecs.keys.sorted()
        let tails = verbs.flatMap { verbSpecs[$0]!.complements } + spec.quantities
        ranked = spec.subjects.keys.sorted().map { ($0, Slot.subject) } + [(spec.negation, .negation)]
            + spec.modals.map { ($0, .modal) } + verbs.map { ($0, .verb) } + tails.map { ($0, .tail) }
            + spec.times.map { ($0, .time) } + spec.places.map { ($0, .place) }
            + spec.interjections.map { ($0, .interjection) }
        var forms: [String: Form] = ["e": Form(slot: nil, lemma: "e")]
        for (word, slot) in slotOf { forms[word.lowercased()] = Form(slot: slot, lemma: word) }
        for person in spec.subjects.values {
            for modal in spec.modals { if let written = person[modal] { forms[written.lowercased()] = Form(slot: .modal, lemma: modal) } }
        }
        for (verb, verbSpec) in spec.verbs {
            for written in verbSpec.present.values { forms[written.lowercased()] = Form(slot: .verb, lemma: verb) }
        }
        self.forms = forms
        longestForm = forms.keys.map { $0.split(separator: " ").count }.max() ?? 1
        phrases = Dictionary(frames().map { (render($0), $0) }) { first, _ in first }
    }

    /// The words of `text` as the grammar wrote them, longest written form first ("para casa",
    /// "gosto de" are one word each). Joined by spaces they give `text` back.
    func units(of text: String) -> [Unit] {
        let words = text.split(separator: " ").map(String.init)
        var units: [Unit] = []
        var i = 0
        while i < words.count {
            var match: (count: Int, form: Form)?
            for count in stride(from: min(longestForm, words.count - i), through: 1, by: -1) {
                let span = words[i..<(i + count)]
                // A comma ends a word: only the last of a span may carry one.
                guard !span.dropLast().contains(where: { $0.hasSuffix(",") }) else { continue }
                let key = span.joined(separator: " ").lowercased()
                if let form = forms[key.hasSuffix(",") ? String(key.dropLast()) : key] {
                    match = (count, form)
                    break
                }
            }
            let count = match?.count ?? 1
            let text = words[i..<(i + count)].joined(separator: " ")
            let bare = text.hasSuffix(",") ? String(text.dropLast()) : text
            units.append(Unit(text: text, slot: match?.form.slot, lemma: match?.form.lemma ?? bare))
            i += count
        }
        return units
    }

    /// `text` entering `phrase` before its word `index` (0 … its number of words), in the order the
    /// person chose: the grammar only conjugates (the subject, wherever it stands, conjugates the
    /// modal, or the verb without one) and punctuates. Strength: in the grammar's own slot order it
    /// is the strength of `fuse`; out of it, one step weaker ("Quero agora ir", medium); with a slot
    /// twice or a word the grammar does not know, weak, and the twin slots meet with "e"
    /// ("Quero comer e beber"); at either end the whole phrases are coordinated.
    func insert(_ text: String, into phrase: String, at index: Int) -> Vocabulary.Combination? {
        guard text != phrase else { return nil }
        let base = units(of: phrase), added = units(of: text)
        let index = min(max(0, index), base.count)
        let before = Array(base[..<index]), after = Array(base[index...])
        let filled = Set(base.compactMap(\.slot))
        let and = [Unit(text: "e", slot: nil, lemma: "e")]
        var units = before + added + after
        if added.contains(where: { $0.slot.map(filled.contains) ?? false }) {
            if after.isEmpty {
                units = base + and + added
            } else if before.isEmpty {
                units = added + and + base
            } else if let slot = added.first?.slot, before.last?.slot == slot {
                units = before + and + added + after
            } else if let slot = added.last?.slot, after.first?.slot == slot {
                units = before + added + and + after
            }
        }
        guard let exact = frame(of: units) else {
            // Weak: suggest from the slots filled first.
            let first = units.reduce(into: Frame(repeating: nil, count: Slot.allCases.count)) { frame, unit in
                if let slot = unit.slot, frame[slot.rawValue] == nil { frame[slot.rawValue] = unit.lemma }
            }
            return Vocabulary.Combination(result: render(units), suggestions: suggestions(for: first), strength: 3)
        }
        let slots = units.compactMap(\.slot)
        let natural = slots == slots.sorted { $0.rawValue < $1.rawValue }
        let strength = min(3, (isStrong(exact) ? 1 : 2) + (natural ? 0 : 1))
        return Vocabulary.Combination(result: render(units), suggestions: suggestions(for: exact), strength: strength)
    }

    func fuse(_ a: String, _ b: String) -> Vocabulary.Combination? {
        guard a != b else { return nil }
        let first = frame(of: a), second = frame(of: b)
        if let first, let second, !zip(first, second).contains(where: { $0 != nil && $1 != nil }) {
            let merged = zip(first, second).map { $0 ?? $1 }
            let text = render(merged)
            let strong = isStrong(merged)
            if !strong { rendered.store(text, merged) }
            return Vocabulary.Combination(result: text, suggestions: suggestions(for: merged), strength: strong ? 1 : 2)
        }
        let (lead, rest) = ordered((a, first), (b, second))
        let joiner: String
        if rank(lead.frame) < 0 {
            joiner = ", "
        } else if lead.frame == nil, let slot = slotOf[rest.text], [.tail, .time, .place].contains(slot) {
            joiner = " "
        } else {
            joiner = " e "
        }
        // Lowercase a phrase's capital, but not an acronym's ("TV").
        let tail = rest.text.dropFirst().first?.isLowercase == true ? rest.text.prefix(1).lowercased() + rest.text.dropFirst() : rest.text
        let suggestions = (lead.frame ?? rest.frame).map(suggestions(for:)) ?? spec.afterComplementSuggest
        let text = lead.text + joiner + tail
        return Vocabulary.Combination(result: text.prefix(1).uppercased() + text.dropFirst(), suggestions: suggestions, strength: 3)
    }

    /// Up to `count` words related to `text`, for a shake: words for the slots right after its last
    /// one first (the natural continuation), then the slots before it; within a slot, the ones
    /// that would make a full phrase. Skips words already present and slots `text` already fills.
    /// A text the grammar did not write continues after a verb.
    func related(to text: String, excluding present: Set<String>, count: Int = 3) -> [String] {
        let frame = frame(of: text)
        let last = frame?.lastIndex { $0 != nil } ?? Slot.verb.rawValue
        func distance(_ slot: Slot) -> Int { slot.rawValue > last ? slot.rawValue - last : 100 + last - slot.rawValue }
        func fit(_ word: String, _ slot: Slot) -> Int {
            guard var merged = frame else { return 1 }
            merged[slot.rawValue] = word
            if merged[Slot.modal.rawValue] == nil { merged[Slot.modal.rawValue] = spec.modals.first }
            return isStrong(merged) ? 0 : 1
        }
        return ranked.enumerated()
            .filter { _, c in c.word != text && !present.contains(c.word) && (frame.map { $0[c.slot.rawValue] == nil } ?? true) }
            .map { offset, c in (word: c.word, key: (distance(c.slot), fit(c.word, c.slot), offset)) }
            .sorted { $0.key < $1.key }
            .prefix(count)
            .map(\.word)
    }

    /// A phrase's frame, or a one-slot frame for a word, or the frame its words fill (a phrase in
    /// the person's order); `nil` for a coordinated text or one the grammar did not write.
    private func frame(of text: String) -> Frame? {
        if let phrase = phrases[text] ?? rendered.frame(text) { return phrase }
        guard let slot = slotOf[text] else { return frame(of: units(of: text)) }
        var frame = Frame(repeating: nil, count: Slot.allCases.count)
        frame[slot.rawValue] = text
        return frame
    }

    /// The frame `units` fill, or `nil` when one has no slot or two share one.
    private func frame(of units: [Unit]) -> Frame? {
        var frame = Frame(repeating: nil, count: Slot.allCases.count)
        for unit in units {
            guard let slot = unit.slot, frame[slot.rawValue] == nil else { return nil }
            frame[slot.rawValue] = unit.lemma
        }
        return frame
    }

    /// Weak fusions read an interjection first, then a text the grammar did not write (an earlier
    /// weak result), then in slot order; ties put the longer text first, then alphabetically.
    private func ordered(_ a: (text: String, frame: Frame?), _ b: (text: String, frame: Frame?)) -> (lead: (text: String, frame: Frame?), rest: (text: String, frame: Frame?)) {
        let key = { (x: (text: String, frame: Frame?)) in (rank(x.frame), -x.text.count, x.text) }
        return key(a) < key(b) ? (a, b) : (b, a)
    }

    /// -1 for a frame led by an interjection, 0 for no frame, else 1 + its first slot.
    private func rank(_ frame: Frame?) -> Int {
        guard let first = frame?.firstIndex(where: { $0 != nil }) else { return 0 }
        return first == Slot.interjection.rawValue ? -1 : first + 1
    }

    /// Every strong phrase: an optional subject and negation, a modal, then optionally a verb with
    /// its complement or quantity and a time.
    private func frames() -> [Frame] {
        var frames: [Frame] = []
        for subject in [nil] + spec.subjects.keys.map(Optional.some) {
            for negation in [nil, spec.negation] {
                for modal in spec.modals {
                    frames.append([nil, subject, negation, modal, nil, nil, nil, nil])
                    for (verb, verbSpec) in spec.verbs {
                        let tails = [nil] + (verbSpec.complements + (verbSpec.quantity ? spec.quantities : [])).map(Optional.some)
                        for tail in tails {
                            for time in [nil] + spec.times.map(Optional.some) {
                                frames.append([nil, subject, negation, modal, verb, tail, time, nil])
                            }
                        }
                    }
                }
            }
        }
        return frames
    }

    /// A phrase of the dataset's grammar: a modal, and a complement or time only after a verb
    /// that takes that complement. Interjections and places are outside it.
    private func isStrong(_ frame: Frame) -> Bool {
        guard frame[Slot.modal.rawValue] != nil, frame[Slot.interjection.rawValue] == nil, frame[Slot.place.rawValue] == nil else { return false }
        let tail = frame[Slot.tail.rawValue]
        guard let verb = frame[Slot.verb.rawValue] else { return tail == nil && frame[Slot.time.rawValue] == nil }
        guard let tail, let verbSpec = spec.verbs[verb] else { return true }
        return verbSpec.complements.contains(tail) || (verbSpec.quantity && spec.quantities.contains(tail))
    }

    /// Without a subject the phrase is in the first person; only an explicit subject is written.
    /// Without a modal the verb is conjugated for an explicit subject, else left in the infinitive.
    private func render(_ frame: Frame) -> String {
        let subject = frame[Slot.subject.rawValue]
        let person = spec.subjects[subject ?? spec.defaultSubject] ?? [:]
        let modal = frame[Slot.modal.rawValue]
        var words: [String] = []
        if subject != nil, let label = person["label"] { words.append(label) }
        if let negation = frame[Slot.negation.rawValue] { words.append(negation) }
        if let modal { words.append(person[modal] ?? modal) }
        if let verb = frame[Slot.verb.rawValue] {
            words.append(modal == nil ? subject.flatMap { spec.verbs[verb]?.present[$0] } ?? verb : verb)
        }
        words += [Slot.tail, .time, .place].compactMap { frame[$0.rawValue] }
        var text = words.joined(separator: " ")
        if let interjection = frame[Slot.interjection.rawValue] {
            text = text.isEmpty ? interjection : interjection + ", " + text
        }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// Words in the person's order: the first subject conjugates the modal, or the verb without a
    /// modal; an interjection stands apart with commas; a word the grammar does not know keeps its
    /// text, lowercased unless it is an acronym ("TV").
    private func render(_ units: [Unit]) -> String {
        let subject = units.first { $0.slot == .subject }?.lemma
        let person = spec.subjects[subject ?? spec.defaultSubject] ?? [:]
        let modal = units.contains { $0.slot == .modal }
        var words = units.map { unit -> String in
            switch unit.slot {
            case .modal: person[unit.lemma] ?? unit.lemma
            case .verb: modal ? unit.lemma : subject.flatMap { spec.verbs[unit.lemma]?.present[$0] } ?? unit.lemma
            case nil: unit.lemma.dropFirst().first?.isLowercase == true ? unit.lemma.prefix(1).lowercased() + unit.lemma.dropFirst() : unit.lemma
            default: unit.lemma
            }
        }
        for (k, unit) in units.enumerated() where unit.slot == .interjection {
            if k < words.count - 1, !words[k].hasSuffix(",") { words[k] += "," }
            if k > 0, !words[k - 1].hasSuffix(",") { words[k - 1] += "," }
        }
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

/// Frames of medium results, shared by every engine call.
private final class FrameCache: Sendable {
    private let frames = Mutex<[String: Grammar.Frame]>([:])
    func frame(_ text: String) -> Grammar.Frame? { frames.withLock { $0[text] } }
    func store(_ text: String, _ frame: Grammar.Frame) { frames.withLock { $0[text] = frame } }
}

private extension Grammar {
    struct Form: Sendable {
        let slot: Slot?
        let lemma: String
    }

    struct Spec: Decodable, Sendable {
        struct Verb: Decodable, Sendable {
            let complements: [String]
            let quantity: Bool
            let suggest: [String]
            /// Present tense by subject, used without a modal.
            let present: [String: String]

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                complements = try c.decode([String].self, forKey: .complements)
                quantity = try c.decodeIfPresent(Bool.self, forKey: .quantity) ?? false
                suggest = try c.decode([String].self, forKey: .suggest)
                present = try c.decodeIfPresent([String: String].self, forKey: .present) ?? [:]
            }

            private enum CodingKeys: String, CodingKey { case complements, quantity, suggest, present }
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
        let places: [String]
        let interjections: [String]
    }

    struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
