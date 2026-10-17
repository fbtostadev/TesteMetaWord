import AVFoundation
import os

/// Interaction sounds, synthesized, meant to stay in the background: only moments that change
/// something (fusion, split, rejection) and the passage over the BubbleKey's gaps make a sound,
/// each a soft low note a few dozen milliseconds long. Touching and approaching stay silent;
/// their feedback is visual, and nothing sounds continuously.
enum SfxCue: CaseIterable {
    case fusion, split, error

    var volume: Float { 1 }

    /// Minimum gap between two plays, so a boundary flicker never machine-guns the sound.
    var cooldown: TimeInterval {
        switch self {
        case .fusion, .split: 0.4
        case .error: 1.0
        }
    }
}

/// Pure functions: every cue is a mono buffer at `sampleRate`. Nothing here touches audio hardware.
enum SfxSynth {
    static let sampleRate = 44_100.0

    // D major pentatonic, low register (warmer and less tiring than the crystalline highs).
    static let d4 = 293.66, fSharp4 = 369.99

    /// Soft glass partials (ratio, gain, decay share): bell-ish inharmonic overtones fade first.
    private static let glass: [(ratio: Double, gain: Double, decay: Double)] = [
        (1, 1, 1), (2.756, 0.28, 0.45), (5.404, 0.1, 0.2),
    ]

    private struct Note {
        var start: Double       // seconds
        var from: Double        // Hz at onset
        var to: Double          // Hz after the glide
        var glide: Double       // glide time constant, seconds
        var decay: Double       // amplitude time constant, seconds
        var gain: Double
        var attack = 0.004
        var partials = SfxSynth.glass
    }

    static func samples(_ cue: SfxCue) -> [Float] {
        switch cue {
        case .fusion:
            // A single soft note that settles on D.
            return render(0.3, [Note(start: 0, from: d4 * 1.04, to: d4, glide: 0.05, decay: 0.07, gain: 0.03, attack: 0.012)])
        case .split:
            // The same note, parting downward.
            return render(0.25, [Note(start: 0, from: fSharp4, to: d4, glide: 0.04, decay: 0.05, gain: 0.03, attack: 0.008)])
        case .error:
            // Not an alarm: one dull low thud. No overtones, so nothing rings.
            return render(0.16, [Note(start: 0, from: 220, to: 207.65, glide: 0.03, decay: 0.03, gain: 0.04,
                                      partials: [(ratio: 1.0, gain: 1.0, decay: 1.0)])])
        }
    }

    /// Quieter than the cues: a passing note is felt more than heard, with barely a hint of bell.
    private static let hush: [(ratio: Double, gain: Double, decay: Double)] = [(1, 1, 1), (2.756, 0.1, 0.3)]

    /// One soft note of `scale` as the dragged word passes over a gap of the BubbleKey: gap
    /// `degree` plays degree `degree`, so sweeping across the phrase runs up the scale.
    static func pass(_ scale: SfxScale, degree: Int) -> [Float] {
        let hz = scale.frequency(degree: degree)
        return render(0.2, [Note(start: 0, from: hz * 1.015, to: hz, glide: 0.02, decay: 0.04, gain: 0.014, attack: 0.01, partials: hush)])
    }

    /// The word settling into the BubbleKey: the root of `scale` and its fifth (or its nearest
    /// degree), the second a breath later, ringing a little longer than a passing note.
    static func snap(_ scale: SfxScale) -> [Float] {
        let fifth = scale.steps.min { abs($0 - 7) < abs($1 - 7) } ?? 7
        let top = SfxScale.root * pow(2, Double(fifth) / 12)
        return render(0.36, [
            Note(start: 0, from: SfxScale.root * 1.02, to: SfxScale.root, glide: 0.04, decay: 0.07, gain: 0.016, attack: 0.01, partials: hush),
            Note(start: 0.045, from: top, to: top, glide: 0.01, decay: 0.06, gain: 0.011, attack: 0.01, partials: hush),
        ])
    }

    private static func render(_ duration: Double, _ notes: [Note]) -> [Float] {
        let count = Int(duration * sampleRate)
        var out = [Double](repeating: 0, count: count)
        for note in notes {
            let first = Int(note.start * sampleRate)
            guard first < count else { continue }
            var phase = 0.0
            for index in first..<count {
                let t = Double(index - first) / sampleRate
                let hz = note.to + (note.from - note.to) * exp(-t / note.glide)
                phase += 2 * .pi * hz / sampleRate
                let onset = min(1, t / note.attack)
                var sample = 0.0
                for part in note.partials {
                    sample += part.gain * sin(phase * part.ratio) * exp(-t / (note.decay * part.decay))
                }
                out[index] += note.gain * onset * sample
            }
        }
        return out.enumerated().map { index, value in
            let tail = min(1, Double(count - index) / (0.01 * sampleRate)) // no click at the end
            return Float(max(-1, min(1, value * tail)))
        }
    }
}

/// A scale for the passage over the BubbleKey. One is drawn at random for each drag, so the same
/// gesture does not always sound the same.
struct SfxScale: Hashable, Sendable {
    let name: String
    /// Semitones above the root, ascending, inside one octave.
    let steps: [Int]

    static let root = SfxSynth.d4
    static let presets = [
        SfxScale(name: "pentatônica maior", steps: [0, 2, 4, 7, 9]),
        SfxScale(name: "pentatônica menor", steps: [0, 3, 5, 7, 10]),
        SfxScale(name: "lídia", steps: [0, 2, 4, 6, 7, 9, 11]),
        SfxScale(name: "dórica", steps: [0, 2, 3, 5, 7, 9, 10]),
        SfxScale(name: "tons inteiros", steps: [0, 2, 4, 6, 8, 10]),
    ]

    /// The most degrees a phrase can climb: two octaves of the scale would leave the warm register.
    var topDegree: Int { 2 * steps.count - 1 }

    /// Degree 0 is the root; past the last step the scale continues an octave higher.
    func frequency(degree: Int) -> Double {
        let degree = min(max(0, degree), topDegree)
        return Self.root * pow(2, Double(steps[degree % steps.count] + 12 * (degree / steps.count)) / 12)
    }

    /// A preset other than `current`, chosen by `pick` (a random index below the count it is given).
    static func next(after current: SfxScale?, pick: (Int) -> Int = { Int.random(in: 0..<$0) }) -> SfxScale {
        let others = presets.filter { $0 != current }
        return others[pick(others.count) % others.count]
    }
}

@MainActor final class Sfx {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SfxSynth.sampleRate, channels: 1)!
    private var players: [SfxCue: AVAudioPlayerNode] = [:]
    private var buffers: [SfxCue: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [SfxCue: TimeInterval] = [:]
    /// Notes of a sweep can overlap, so they take turns on a few players.
    private var notePlayers: [AVAudioPlayerNode] = []
    private var nextNotePlayer = 0
    private var noteBuffers: [String: AVAudioPCMBuffer] = [:]
    private var lastPass = -TimeInterval.infinity
    private var loaded = false
    /// The scale of the current drag; `rollScale` draws a new one.
    private(set) var scale = SfxScale.next(after: nil)

    /// Minimum gap between two notes of a sweep.
    private static let passCooldown: TimeInterval = 0.08

    func play(_ cue: SfxCue) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - (lastPlayed[cue] ?? -.infinity) >= cue.cooldown, load(), let player = players[cue],
              let buffer = buffers[cue] else { return }
        lastPlayed[cue] = now
        guard startEngine() else { return }
        player.stop()
        player.volume = cue.volume
        player.scheduleBuffer(buffer)
        player.play()
    }

    /// A new drag starts: draw its scale, never the one just heard.
    func rollScale() {
        scale = SfxScale.next(after: scale)
    }

    /// The dragged word passes over gap `degree` of the BubbleKey.
    func pass(degree: Int) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPass >= Self.passCooldown else { return }
        lastPass = now
        playNote("\(scale.name)-\(min(max(0, degree), scale.topDegree))") { SfxSynth.pass(scale, degree: degree) }
    }

    /// The word settles into the BubbleKey.
    func snap() {
        playNote("\(scale.name)-snap") { SfxSynth.snap(scale) }
    }

    private func playNote(_ key: String, samples: () -> [Float]) {
        guard load(), startEngine() else { return }
        if noteBuffers[key] == nil { noteBuffers[key] = makeBuffer(samples()) }
        guard let buffer = noteBuffers[key] else { return }
        let player = notePlayers[nextNotePlayer]
        nextNotePlayer = (nextNotePlayer + 1) % notePlayers.count
        player.stop()
        player.scheduleBuffer(buffer)
        player.play()
    }

    private func startEngine() -> Bool {
        if !engine.isRunning { try? engine.start() }
        return engine.isRunning
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }

    private func load() -> Bool {
        if loaded { return !buffers.isEmpty }
        loaded = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        for cue in SfxCue.allCases {
            guard let buffer = makeBuffer(SfxSynth.samples(cue)) else { continue }
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players[cue] = player
            buffers[cue] = buffer
        }
        for _ in 0..<4 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            notePlayers.append(player)
        }
        return !buffers.isEmpty
    }
}
