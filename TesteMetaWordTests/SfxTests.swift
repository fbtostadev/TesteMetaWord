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
}
