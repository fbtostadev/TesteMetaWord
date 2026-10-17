import AVFoundation
import CoreGraphics

/// Tension before a long-press split: the master bubble trembles and hums louder for the whole
/// press, then pops at the instant it divides. iPad has no Taptic Engine, so sound stands in
/// for haptics. Curves and sounds are pure functions; `SplitSound` only plays them.
enum SplitTension {
    /// Same as the long-press duration: the pop lands on the split.
    static let duration: TimeInterval = 0.6
    static let maxAmplitude: CGFloat = 2.5
    static let maxSwell: CGFloat = 0.04
    static let sampleRate = 44_100.0

    static func progress(since start: TimeInterval, now: TimeInterval) -> Double {
        min(1, max(0, (now - start) / duration))
    }

    /// Mostly horizontal jitter whose amplitude grows with progress².
    static func offset(progress: Double, time: TimeInterval) -> CGSize {
        let amplitude = maxAmplitude * CGFloat(progress * progress) / hypot(1, 0.5)
        return CGSize(width: amplitude * CGFloat(sin(2 * .pi * 29 * time)),
                      height: amplitude * 0.5 * CGFloat(sin(2 * .pi * 41 * time + 0.7)))
    }

    static func scale(progress: Double) -> CGFloat {
        1 + maxSwell * CGFloat(progress * progress)
    }

    /// A soft low hum whose tremolo speeds up (9 → 30 Hz), pitch rises slightly and volume swells.
    static func tremorSamples() -> [Float] {
        let count = Int(duration * sampleRate)
        var carrier = 0.0, tremolo = 0.0
        return (0..<count).map { index in
            let p = Double(index) / Double(count)
            carrier += 2 * .pi * (196 + 37 * p) / sampleRate
            tremolo += 2 * .pi * (9 + 21 * p) / sampleRate
            let depth = 1 - 0.8 * (0.5 - 0.5 * sin(tremolo))
            let tail = min(1, Double(count - index) / (0.008 * sampleRate)) // no click at the end
            let tone = (sin(carrier) + 0.35 * sin(2 * carrier)) / 1.35
            return Float(0.09 * p * p * depth * tail * tone)
        }
    }
}

/// Plays the tension hum and the split chime. Ambient audio: respects silent mode and mixes with others.
@MainActor final class SplitSound {
    private let engine = AVAudioEngine()
    private let hum = AVAudioPlayerNode()
    private let pop = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SplitTension.sampleRate, channels: 1)!
    private var humBuffer: AVAudioPCMBuffer?
    private var popBuffer: AVAudioPCMBuffer?
    /// Bumped on every begin, so a fade from an earlier press never stops a newer one.
    private var generation = 0

    func begin() {
        guard start(), let humBuffer else { return }
        generation += 1
        hum.stop()
        hum.volume = 1
        hum.scheduleBuffer(humBuffer)
        hum.play()
    }

    /// Released early or turned into a drag: the hum fades out, no pop.
    func cancel() { fadeHum() }

    func burst() {
        guard start(), let popBuffer else { return }
        fadeHum()
        pop.stop()
        pop.scheduleBuffer(popBuffer)
        pop.play()
    }

    private func start() -> Bool {
        if humBuffer == nil {
            try? AVAudioSession.sharedInstance().setCategory(.ambient)
            engine.attach(hum)
            engine.attach(pop)
            humBuffer = buffer(SplitTension.tremorSamples())
            popBuffer = buffer(SfxSynth.samples(.split))
            engine.connect(hum, to: engine.mainMixerNode, format: humBuffer?.format ?? format)
            engine.connect(pop, to: engine.mainMixerNode, format: popBuffer?.format ?? format)
        }
        if !engine.isRunning { try? engine.start() }
        return engine.isRunning
    }

    private func fadeHum() {
        guard hum.isPlaying else { return }
        let current = generation
        Task { @MainActor in
            for volume: Float in [0.6, 0.3, 0.1] {
                guard generation == current else { return }
                hum.volume = volume
                try? await Task.sleep(for: .milliseconds(10))
            }
            if generation == current { hum.stop() }
        }
    }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }
}
