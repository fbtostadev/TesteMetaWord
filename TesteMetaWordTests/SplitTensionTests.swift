import Testing
import Foundation
@testable import TesteMetaWord

struct SplitTensionTests {
    @Test func progressRunsFromPressToSplit() {
        #expect(SplitTension.progress(since: 10, now: 9) == 0)
        #expect(abs(SplitTension.progress(since: 10, now: 10.3) - 0.5) < 1e-9)
        #expect(SplitTension.progress(since: 10, now: 12) == 1)
    }

    @Test func tremorGrowsAndStaysSmall() {
        let times = stride(from: 0.0, to: 0.5, by: 0.004)
        func peak(_ progress: Double) -> CGFloat {
            times.map { let o = SplitTension.offset(progress: progress, time: $0); return hypot(o.width, o.height) }.max() ?? 0
        }
        #expect(peak(0) == 0)
        #expect(peak(0.3) < peak(1) / 4)
        #expect(peak(1) > SplitTension.maxAmplitude * 0.7)
        #expect(peak(1) <= SplitTension.maxAmplitude + 0.001)
        #expect(SplitTension.scale(progress: 0) == 1)
        #expect(abs(SplitTension.scale(progress: 1) - (1 + SplitTension.maxSwell)) < 0.0001)
    }

    @Test func tremorSoundLastsThePressAndCrescendos() {
        let samples = SplitTension.tremorSamples()
        #expect(samples.count == Int(SplitTension.duration * SplitTension.sampleRate))
        #expect(samples.allSatisfy { abs($0) <= 1 })
        let fifth = samples.count / 5
        #expect(rms(samples.suffix(fifth)) > 4 * rms(samples.prefix(fifth)))
    }

    @Test func popIsShortWithItsPeakAtTheStart() {
        let samples = SplitTension.popSamples()
        let seconds = Double(samples.count) / SplitTension.sampleRate
        #expect(seconds > 0.05 && seconds <= 0.12)
        #expect(samples.allSatisfy { abs($0) <= 1 })
        let peakIndex = samples.indices.max { abs(samples[$0]) < abs(samples[$1]) } ?? 0
        #expect(Double(peakIndex) / SplitTension.sampleRate < 0.01)
        #expect(rms(samples.suffix(samples.count / 10)) < 0.01)
    }

    private func rms<C: Collection<Float>>(_ samples: C) -> Float {
        (samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, samples.count))).squareRoot()
    }
}
