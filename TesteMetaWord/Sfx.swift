import AVFoundation
import os

/// Interaction sounds, synthesized, meant to stay in the background: only rare moments that change
/// something (fusion, split, rejection) make a sound, each a single soft low note a few dozen
/// milliseconds long. Frequent gestures (touch, approach) stay silent; their feedback is visual.
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

@MainActor final class Sfx {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SfxSynth.sampleRate, channels: 1)!
    private var players: [SfxCue: AVAudioPlayerNode] = [:]
    private var buffers: [SfxCue: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [SfxCue: TimeInterval] = [:]
    private var loaded = false
    var muted = false

    func play(_ cue: SfxCue) {
        let now = ProcessInfo.processInfo.systemUptime
        guard !muted, now - (lastPlayed[cue] ?? -.infinity) >= cue.cooldown, load(), let player = players[cue],
              let buffer = buffers[cue] else { return }
        lastPlayed[cue] = now
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        player.stop()
        player.volume = cue.volume
        player.scheduleBuffer(buffer)
        player.play()
    }

    private func load() -> Bool {
        if loaded { return !buffers.isEmpty }
        loaded = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        for cue in SfxCue.allCases {
            let samples = SfxSynth.samples(cue)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { continue }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players[cue] = player
            buffers[cue] = buffer
        }
        return !buffers.isEmpty
    }
}

/// A continuous background tone tied to the overlap depth of an approaching pair: silent apart,
/// it rises from D4 toward the fifth A4 as the surfaces sink into each other, and gets slightly
/// louder, never above background level. Parameters are smoothed so it never clicks.
enum DepthTone {
    static let maxLevel = 0.035
    static let lowHz = 293.66, highHz = 440.0

    static func frequency(depth: Double) -> Double {
        lowHz * pow(highHz / lowHz, min(1, max(0, depth)))
    }

    static func level(depth: Double) -> Double {
        maxLevel * pow(min(1, max(0, depth)), 1.5)
    }
}

/// Real-time voice behind `DepthTone`. The audio thread reads `target`; the main actor writes it.
final class DepthVoice: @unchecked Sendable {
    private let target = OSAllocatedUnfairLock(initialState: (hz: DepthTone.lowHz, level: 0.0))
    private var phase = 0.0, hz = DepthTone.lowHz, level = 0.0
    private let rate: Double

    init(sampleRate: Double) { rate = sampleRate }

    func set(depth: Double) {
        target.withLock { $0 = (DepthTone.frequency(depth: depth), DepthTone.level(depth: depth)) }
    }

    /// Built here, not in the main-actor `DepthSound`: a closure created in a main-actor method
    /// inherits that isolation, and Swift would assert on the main queue from the audio thread.
    nonisolated func makeNode(format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { [self] _, _, frames, buffers in
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            guard let data = list.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            render(data, frames: Int(frames))
            return noErr
        }
    }

    func render(_ out: UnsafeMutablePointer<Float>, frames: Int) {
        let goal = target.withLock { $0 }
        let step = 1 - exp(-1 / (0.03 * rate)) // ~30 ms smoothing
        for index in 0..<frames {
            hz += (goal.hz - hz) * step
            level += (goal.level - level) * step
            phase += 2 * .pi * hz / rate
            if phase > 2 * .pi { phase -= 2 * .pi }
            out[index] = Float(level * (sin(phase) + 0.25 * sin(2 * phase)) / 1.25)
        }
    }
}

@MainActor final class DepthSound {
    private let engine = AVAudioEngine()
    private let voice = DepthVoice(sampleRate: SfxSynth.sampleRate)
    private var attached = false
    var muted = false { didSet { if muted { voice.set(depth: 0) } } }

    func update(depth: Double) {
        guard !muted else { return voice.set(depth: 0) }
        if depth > 0, !start() { return }
        voice.set(depth: depth)
    }

    private func start() -> Bool {
        if !attached {
            attached = true
            try? AVAudioSession.sharedInstance().setCategory(.ambient)
            let format = AVAudioFormat(standardFormatWithSampleRate: SfxSynth.sampleRate, channels: 1)!
            let node = voice.makeNode(format: format)
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        if !engine.isRunning { try? engine.start() }
        return engine.isRunning
    }
}
