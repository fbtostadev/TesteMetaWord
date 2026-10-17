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

    init(_ text: String, fusionCount: Int = 0, glassID: UUID? = nil, phase: Double) {
        self.id = UUID()
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
    private var approachTarget: UUID?
    private var advanceDepth = 0.0
    private var advancedAt: TimeInterval = 0
    var calibration = Calibration() { didSet { cancel() } }
    private var history: [(chips: [WordChip], result: UUID)] = []

    init(engine: any CompositionEngine = RuleEngine()) {
        self.engine = engine
        let rules = RuleEngine.lexicon(for: Vocabulary.initial, focus: nil)
        lexicon = rules
        fusions = rules.fusions
    }

    var canUndo: Bool { !history.isEmpty }
    var latestResult: UUID? { history.last?.result }

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
    var activePair: MergePair? {
        candidate ?? pinching ?? dragging.flatMap { source in approachTarget.map { MergePair(source: source, target: $0) } }
    }

    func compatible(_ a: UUID, _ b: UUID) -> Bool {
        guard let first = chips.first(where: { $0.id == a }), let second = chips.first(where: { $0.id == b }) else { return false }
        return first.text != second.text && fusions[[first.text, second.text]] != nil
    }

    func tap(_ id: UUID) {
        guard chips.contains(where: { $0.id == id }), dragging == nil, pinching == nil else { return }
        if let candidate, candidate.contains(id) { confirm(); return }
        if let selected, selected != id, compatible(selected, id) {
            candidate = MergePair(source: selected, target: id)
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
            return
        }
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
        cancel()
        candidate = pair
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
    }

    private func confirm() {
        guard let pair = candidate,
              let a = chips.first(where: { $0.id == pair.source }),
              let b = chips.first(where: { $0.id == pair.target }),
              let combination = fusions[[a.text, b.text]] else { return }
        let result = WordChip(combination.result, fusionCount: a.fusionCount + b.fusionCount + 1, glassID: a.glassID, phase: a.phase)
        history.append((chips, result.id))
        let index = chips.firstIndex(where: { pair.contains($0.id) }) ?? 0
        chips.removeAll { pair.contains($0.id) }
        chips.insert(result, at: min(index, chips.count))
        let fresh = combination.suggestions.filter { text in !chips.contains { $0.text == text } }
        for (k, text) in fresh.enumerated() {
            chips.append(WordChip(text, phase: result.phase + Physics.familyLag * Double(k + 1)))
        }
        cancel()
    }

    func undo(from id: UUID? = nil) {
        guard id == nil || id == latestResult, let snapshot = history.popLast() else { return }
        chips = snapshot.chips
        cancel()
    }
}
