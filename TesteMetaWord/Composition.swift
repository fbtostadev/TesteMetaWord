import Foundation
import Observation

struct WordChip: Identifiable, Equatable {
    let id: UUID
    let text: String
    let fusionCount: Int
    let glassID: UUID
    /// Idle orbit phase. A fusion result keeps its first origin's phase and each suggestion
    /// lags it by `Physics.familyLag`, so words from one origin float in sync.
    let phase: Double
    var scale: Double { 1 + min(0.24, Double(fusionCount) * 0.04) }

    init(_ text: String, fusionCount: Int = 0, glassID: UUID? = nil, phase: Double, id: UUID = UUID()) {
        self.id = id
        self.text = text
        self.fusionCount = fusionCount
        self.glassID = glassID ?? id
        self.phase = phase
    }
}

struct MergePair: Equatable {
    let source: UUID
    let target: UUID
    func contains(_ id: UUID) -> Bool { source == id || target == id }
}

struct Calibration: Equatable {
    var distance: Double = 24
}

@MainActor @Observable final class Composition {
    /// Initial phases step by the golden angle, so neighbors rarely float in lockstep.
    private(set) var chips = Vocabulary.initial.enumerated().map { WordChip($0.element, phase: Double($0.offset) * 2.39996) }
    /// Last lexicon applied for the current words; gestures read only this and `fusions`.
    private(set) var lexicon: Lexicon
    /// Every fusion learned this session, keyed by text, so Undo finds earlier ones again.
    private var fusions: [Set<String>: Vocabulary.Combination]
    private let engine: any CompositionEngine
    private(set) var selected: UUID?
    /// Tap-prepared pair waiting for a confirming tap; also the dropped pair while it fuses.
    private(set) var candidate: MergePair?
    private(set) var dragging: UUID?
    /// Two chips held by one finger each; `source` is the one whose identity a fusion keeps.
    private(set) var pinching: MergePair?
    private(set) var resistance = 0.0
    /// Pair armed by deep overlap during a drag; releasing confirms it.
    private(set) var dropCandidate: MergePair?
    /// Compatible chip within approach distance of the one being handled.
    private(set) var approachTarget: UUID?
    /// Overlap depth of the armed-capable pair being approached, 0 (touching or apart) to 1; drives the continuous tone.
    private(set) var depth = 0.0
    /// Gap of the BubbleKey's phrase where the other word of the active pair enters, before word
    /// `insertion` (0 … its number of words); nil when the pair does not hold the BubbleKey.
    private(set) var insertion: Int?
    private var advanceDepth = 0.0
    private var advancedAt: TimeInterval = 0
    var calibration = Calibration() { didSet { cancel() } }
    /// One act, for Undo: the words before it and, for a fusion, its result, the origins it
    /// consumed and the suggestions it budded, so the result can still split after later acts.
    private struct Act {
        let chips: [WordChip]
        var result: UUID?
        var origins: [WordChip] = []
        var budded: Set<UUID> = []
    }
    private var history: [Act] = []
    /// Words the latest act brought in; a passive fusion keeps the older twin.
    private var born: Set<UUID> = []

    /// `initial` is the lexicon of the initial words until the engine first answers.
    init(engine: any CompositionEngine = RuleEngine(), initial: Lexicon = RuleEngine.lexicon(for: Vocabulary.initial, focus: nil)) {
        self.engine = engine
        lexicon = initial
        fusions = initial.fusions
    }

    var canUndo: Bool { !history.isEmpty }
    /// Result of the latest fusion still on the canvas, even under later shakes or splits.
    var latestResult: UUID? {
        history.reversed().lazy.compactMap(\.result).first { id in chips.contains { $0.id == id } }
    }
    /// The result a long press divides: the latest fusion still standing.
    var splittable: UUID? { latestResult }

    /// Chips whose text another chip already shows, each with the twin that absorbs it: the
    /// latest result, else a word that was already there, else the first one.
    var duplicates: [(duplicate: UUID, keeper: UUID)] {
        Dictionary(grouping: chips, by: \.text).values.filter { $0.count > 1 }.flatMap { twins in
            let keeper = twins.first { $0.id == latestResult } ?? twins.first { !born.contains($0.id) } ?? twins[0]
            return twins.filter { $0.id != keeper.id }.map { ($0.id, keeper.id) }
        }
    }

    /// Optical center: the latest fusion result, or else the engine's pick.
    var focus: UUID? {
        latestResult ?? chips.first { $0.text == lexicon.focus }?.id
    }

    /// Atmosphere zone of every word except the focus. Words the engine has not ranked yet wait
    /// in the middle zone.
    var zones: [UUID: Int] {
        guard let focus else { return [:] }
        return Dictionary(uniqueKeysWithValues: chips.filter { $0.id != focus }.map { ($0.id, lexicon.zones[$0.text] ?? 2) })
    }

    /// Asks the engine about the current words. A lexicon that arrives after the words changed
    /// is dropped; the next refresh covers the new words.
    func refresh() async {
        let words = chips.map(\.text)
        let focusText = latestResult.flatMap { id in chips.first { $0.id == id }?.text }
        let next = await engine.lexicon(for: words, focus: focusText)
        guard words == chips.map(\.text) else { return }
        fusions.merge(next.fusions) { _, new in new }
        lexicon = next
    }
    /// Words of the BubbleKey's phrase, once the engine has read this BubbleKey.
    var focusPhrase: [String]? {
        guard let focus, chips.first(where: { $0.id == focus })?.text == lexicon.focus, !lexicon.phrase.isEmpty else { return nil }
        return lexicon.phrase
    }

    /// The word of `pair` that enters the BubbleKey's phrase, when the pair holds the BubbleKey.
    func entering(_ pair: MergePair) -> WordChip? {
        guard let focus, focusPhrase != nil, pair.contains(focus) else { return nil }
        let other = pair.source == focus ? pair.target : pair.source
        return chips.first { $0.id == other && lexicon.insertions[$0.text] != nil }
    }

    /// The fusion at each gap of the BubbleKey for `pair`.
    private func insertions(_ pair: MergePair) -> [Vocabulary.Combination]? {
        entering(pair).flatMap { lexicon.insertions[$0.text] }
    }

    /// Where the grammar reads the pair best: the strongest gap, the last on ties. Gestures that
    /// do not point at a gap (tap, pinch, dragging the BubbleKey itself) start there.
    func naturalGap(_ pair: MergePair) -> Int? {
        guard let options = insertions(pair), let best = options.map(\.strength).min() else { return nil }
        return options.lastIndex { $0.strength == best }
    }

    /// The dragged word is choosing a gap in the BubbleKey; this takes priority over a shake.
    var choosingGap: Bool { dragging != nil && insertion != nil }

    /// While a dragged word is over the BubbleKey: the gap under the finger.
    func updateInsertion(_ gap: Int?) {
        guard dragging != nil, let gap, let pair = activePair, let count = insertions(pair)?.count else {
            insertion = nil
            return
        }
        insertion = min(max(0, gap), count - 1)
    }

    /// Keyboard and VoiceOver: moves the prepared pair's gap by `step` words.
    func moveInsertion(by step: Int) {
        guard let candidate, let insertion, let count = insertions(candidate)?.count else { return }
        self.insertion = min(max(0, insertion + step), count - 1)
    }

    var activePair: MergePair? {
        candidate ?? pinching ?? dragging.flatMap { source in approachTarget.map { MergePair(source: source, target: $0) } }
    }

    /// A pinch whose pair cannot fuse and whose surfaces already touch: only the membrane resists.
    var rejecting: Bool {
        guard let pinching else { return false }
        return resistance > 0 && !compatible(pinching.source, pinching.target)
    }

    /// Strength of the known fusion of two chips (1 strong … 3 weak), if any.
    func strength(_ a: UUID, _ b: UUID) -> Int? {
        guard let first = chips.first(where: { $0.id == a }), let second = chips.first(where: { $0.id == b }) else { return nil }
        return fusions[[first.text, second.text]]?.strength
    }

    func compatible(_ a: UUID, _ b: UUID) -> Bool {
        guard let first = chips.first(where: { $0.id == a }), let second = chips.first(where: { $0.id == b }) else { return false }
        return first.text != second.text && fusions[[first.text, second.text]] != nil
    }

    func tap(_ id: UUID) {
        guard chips.contains(where: { $0.id == id }), dragging == nil, pinching == nil else { return }
        if let candidate, candidate.contains(id) { confirm(); return }
        if let selected, selected != id, compatible(selected, id) {
            let pair = MergePair(source: selected, target: id)
            candidate = pair
            insertion = naturalGap(pair)
        } else {
            let wasSelected = selected == id
            cancel()
            selected = wasSelected ? nil : id
        }
    }

    func beginDrag(_ id: UUID) {
        cancel()
        dragging = id
    }

    func beginPinch(_ a: UUID, _ b: UUID) {
        cancel()
        pinching = MergePair(source: a, target: b)
    }

    func updateProximity(target: UUID?, penetration: Double, time: TimeInterval) {
        guard let dragging else { return }
        approach(dragging, target, penetration: penetration, time: time)
    }

    /// `penetration` is nil while the two surfaces are farther apart than the approach distance.
    /// An incompatible pair never arms; its membrane only resists once the surfaces touch.
    func updatePinch(penetration: Double?, time: TimeInterval) {
        guard let pinching else { return }
        guard compatible(pinching.source, pinching.target) else {
            approachTarget = nil
            dropCandidate = nil
            depth = 0
            resistance = min(1, max(0, (penetration ?? 0) / 0.25))
            return
        }
        approach(pinching.source, penetration == nil ? nil : pinching.target, penetration: penetration ?? 0, time: time)
    }

    /// Shared by drag and pinch: deep overlap arms, stalling before it builds resistance.
    private func approach(_ source: UUID, _ target: UUID?, penetration: Double, time: TimeInterval) {
        guard let target, compatible(source, target) else {
            approachTarget = nil
            dropCandidate = nil
            resistance = 0
            depth = 0
            return
        }
        depth = min(1, max(0, penetration))
        if approachTarget != target {
            approachTarget = target
            advanceDepth = penetration
            advancedAt = time
        }
        if penetration - advanceDepth >= 0.035 {
            advanceDepth = penetration
            advancedAt = time
        } else if penetration < advanceDepth {
            advanceDepth = penetration
        }
        guard penetration >= 0.45 else {
            dropCandidate = nil
            resistance = min(1, max(0, (time - advancedAt - 0.25) / 0.3))
            return
        }
        resistance = 0
        dropCandidate = MergePair(source: source, target: target)
    }

    /// Releasing an armed pair returns it as the candidate; the view confirms it after the
    /// convergence animation. Without an armed pair the word simply stays where it was dropped.
    @discardableResult func endDrag() -> MergePair? {
        guard dragging != nil else { return nil }
        return release()
    }

    /// The first finger lifting ends the pinch, with the same outcome as releasing a drag.
    @discardableResult func endPinch() -> MergePair? {
        guard pinching != nil else { return nil }
        return release()
    }

    private func release() -> MergePair? {
        let pair = dropCandidate
        let gap = pair.flatMap { insertions($0) == nil ? nil : insertion ?? naturalGap($0) }
        cancel()
        candidate = pair
        insertion = gap
        return pair
    }

    func cancel() {
        selected = nil
        candidate = nil
        dropCandidate = nil
        dragging = nil
        pinching = nil
        approachTarget = nil
        resistance = 0
        depth = 0
        insertion = nil
    }

    /// A pair holding the BubbleKey fuses at its gap; any other fuses as a whole.
    private func confirm() {
        guard let pair = candidate,
              let a = chips.first(where: { $0.id == pair.source }),
              let b = chips.first(where: { $0.id == pair.target }),
              let combination = insertion.flatMap({ insertions(pair)?[$0] }) ?? fusions[[a.text, b.text]] else { return }
        let result = WordChip(combination.result, fusionCount: a.fusionCount + b.fusionCount + 1, glassID: a.glassID, phase: a.phase)
        var act = Act(chips: chips, result: result.id, origins: [a, b])
        let index = chips.firstIndex(where: { pair.contains($0.id) }) ?? 0
        chips.removeAll { pair.contains($0.id) }
        chips.insert(result, at: min(index, chips.count))
        let fresh = combination.suggestions.filter { text in !chips.contains { $0.text == text } }
        for (k, text) in fresh.enumerated() {
            let suggestion = WordChip(text, phase: result.phase + Physics.familyLag * Double(k + 1))
            chips.append(suggestion)
            act.budded.insert(suggestion.id)
        }
        history.append(act)
        born = act.budded.union([result.id])
        cancel()
    }

    /// Shake: the bubble buds the engine's related words, keeping its place. True if any budded.
    @discardableResult func derive(from id: UUID) -> Bool {
        guard let chip = chips.first(where: { $0.id == id }) else { return false }
        let present = Set(chips.map(\.text))
        let words = (lexicon.related[chip.text] ?? []).filter { !present.contains($0) }
        guard !words.isEmpty else { return false }
        history.append(Act(chips: chips))
        let budded = words.enumerated().map { k, text in WordChip(text, phase: chip.phase + Physics.familyLag * Double(k + 1)) }
        chips += budded
        born = Set(budded.map(\.id))
        cancel()
        return true
    }

    /// Long press: the latest fusion result splits back into its origins, even after later acts.
    /// Right after the fusion this is its Undo; after a shake or another split the origins come
    /// back in the result's place, its remaining suggestions leave, later words stay, and the
    /// split is an act of its own. Origins whose text is already shown fuse passively afterwards.
    @discardableResult func split(_ id: UUID) -> Bool {
        guard id == latestResult, let index = history.lastIndex(where: { $0.result == id }) else { return false }
        if index == history.count - 1 {
            undo()
            return true
        }
        let fusion = history[index]
        history.append(Act(chips: chips))
        let position = chips.firstIndex { $0.id == id } ?? chips.count
        chips.removeAll { $0.id == id || fusion.budded.contains($0.id) }
        chips.insert(contentsOf: fusion.origins, at: min(position, chips.count))
        born = Set(fusion.origins.map(\.id))
        cancel()
        return true
    }

    /// Passive fusion: each duplicate dissolves into its twin, which keeps the larger fusion count.
    /// Part of the act that created the duplicate, so one Undo reverts both.
    func absorbDuplicates() {
        for (duplicate, keeper) in duplicates {
            guard let gone = chips.first(where: { $0.id == duplicate }),
                  let k = chips.firstIndex(where: { $0.id == keeper }) else { continue }
            let kept = chips[k]
            if gone.fusionCount > kept.fusionCount {
                chips[k] = WordChip(kept.text, fusionCount: gone.fusionCount, glassID: kept.glassID, phase: kept.phase, id: kept.id)
            }
            chips.removeAll { $0.id == duplicate }
        }
        cancel()
    }

    func undo() {
        guard let snapshot = history.popLast() else { return }
        chips = snapshot.chips
        born = []
        cancel()
    }
}
