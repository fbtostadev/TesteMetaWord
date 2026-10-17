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

    @Test func thereAreThreeToFivePresetsAndEachClimbsInsideOneOctave() {
        #expect((3...5).contains(SfxScale.presets.count))
        for scale in SfxScale.presets {
            #expect(scale.steps.first == 0, "\(scale.name)")
            #expect(scale.steps == scale.steps.sorted() && Set(scale.steps).count == scale.steps.count, "\(scale.name)")
            #expect(scale.steps.allSatisfy { (0..<12).contains($0) }, "\(scale.name)")
        }
        #expect(Set(SfxScale.presets.map(\.name)).count == SfxScale.presets.count)
    }

    @Test func eachGapPlaysTheNextDegreeAndPastTheLastItContinuesAnOctaveUp() {
        for scale in SfxScale.presets {
            let notes = (0...scale.topDegree).map(scale.frequency(degree:))
            #expect(notes == notes.sorted() && Set(notes).count == notes.count, "\(scale.name)")
            #expect(abs(scale.frequency(degree: 0) - SfxScale.root) < 0.001)
            #expect(abs(scale.frequency(degree: scale.steps.count) / SfxScale.root - 2) < 0.001, "o grau seguinte à escala é a oitava")
            #expect(scale.frequency(degree: 99) == scale.frequency(degree: scale.topDegree), "frases longas não saem do registro grave")
            #expect(scale.frequency(degree: -3) == scale.frequency(degree: 0))
        }
    }

    @Test func aNewDragNeverRepeatsTheScaleJustHeard() {
        for scale in SfxScale.presets {
            for pick in 0..<SfxScale.presets.count {
                #expect(SfxScale.next(after: scale, pick: { $0 - 1 - min(pick, $0 - 1) }) != scale)
            }
        }
        #expect(Set((0..<200).map { _ in SfxScale.next(after: nil) }).count == SfxScale.presets.count, "todas saem ao acaso")
    }

    @Test func passingNotesAndTheSnapAreShortQuietAndEndSilent() {
        for scale in SfxScale.presets {
            let notes = (0...scale.topDegree).map { SfxSynth.pass(scale, degree: $0) } + [SfxSynth.snap(scale)]
            for samples in notes {
                let seconds = Double(samples.count) / SfxSynth.sampleRate
                #expect(seconds >= 0.15 && seconds <= 0.8)
                #expect(samples.allSatisfy { $0.isFinite && abs($0) <= 0.1 }, "\(scale.name)")
                #expect(samples.contains { abs($0) > 0.01 }, "\(scale.name)")
                #expect(abs(samples.last ?? 1) < 0.001)
            }
        }
    }

    @Test func theSnapRingsLongerThanAPassingNote() {
        let scale = SfxScale.presets[0]
        #expect(SfxSynth.snap(scale).count > SfxSynth.pass(scale, degree: 0).count)
    }
}
