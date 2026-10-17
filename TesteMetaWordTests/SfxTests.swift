import Testing
import Foundation
@testable import TesteMetaWord

struct SfxTests {
    @Test(arguments: SfxCue.allCases)
    func everyCueIsShortFiniteQuietAndEndsSilent(cue: SfxCue) {
        let samples = SfxSynth.samples(cue)
        let seconds = Double(samples.count) / SfxSynth.sampleRate
        #expect(seconds >= 0.15 && seconds <= 0.8)
        #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 0.1 }) // background level
        #expect(samples.contains { abs($0) > 0.01 })
        #expect(abs(samples.last ?? 1) < 0.001)
    }

    @Test func errorIsDullerAndShorterThanTheFusionChime() {
        #expect(SfxSynth.samples(.error).count < SfxSynth.samples(.fusion).count)
    }

    @Test func depthToneRisesWithDepthAndStaysAtBackgroundLevel() {
        #expect(DepthTone.level(depth: 0) == 0)
        #expect(abs(DepthTone.frequency(depth: 0) - DepthTone.lowHz) < 0.001)
        #expect(abs(DepthTone.frequency(depth: 1) - DepthTone.highHz) < 0.001)
        var last = (hz: 0.0, level: -1.0)
        for step in 0...10 {
            let depth = Double(step) / 10
            let now = (hz: DepthTone.frequency(depth: depth), level: DepthTone.level(depth: depth))
            #expect(now.hz >= last.hz && now.level >= last.level)
            last = now
        }
        #expect(DepthTone.level(depth: 5) <= DepthTone.maxLevel)
        #expect(DepthTone.maxLevel <= 0.04)
    }

    @Test func depthVoiceFadesInSmoothlyAndOutToSilence() {
        let voice = DepthVoice(sampleRate: SfxSynth.sampleRate)
        var block = [Float](repeating: 0, count: 4410)
        voice.set(depth: 1)
        block.withUnsafeMutableBufferPointer { voice.render($0.baseAddress!, frames: $0.count) }
        #expect(block.allSatisfy { $0.isFinite && abs($0) <= 0.04 })
        #expect(abs(block[0]) < 0.001)
        #expect(block.suffix(500).contains { abs($0) > 0.01 })
        voice.set(depth: 0)
        for _ in 0..<3 { block.withUnsafeMutableBufferPointer { voice.render($0.baseAddress!, frames: $0.count) } }
        #expect(block.allSatisfy { abs($0) < 0.0005 })
    }
}
