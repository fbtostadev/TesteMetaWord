import Testing
import UIKit
@testable import TesteMetaWord

struct PhraseLayoutTests {
    /// "Quero e ir" with hand-set glyph frames: 60, 10 and 16 pt words, 6 pt spaces, in a capsule
    /// with 24 pt of padding.
    static let layout = PhraseLayout(
        words: [CGRect(x: 24, y: 16, width: 60, height: 24), CGRect(x: 90, y: 16, width: 10, height: 24), CGRect(x: 106, y: 16, width: 16, height: 24)],
        size: CGSize(width: 146, height: 56))

    @Test func theTextLayoutFramesEveryWordInOrder() throws {
        let font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        let words = ["Quero", "ir", "para casa"]
        let natural = (words.joined(separator: " ") as NSString).size(withAttributes: [.font: font]).width
        let size = CGSize(width: ceil(natural) + 48, height: 56)
        let layout = try #require(PhraseLayout(words, font: font, size: size, padding: 24))
        #expect(layout.words.count == 3)
        for (a, b) in zip(layout.words, layout.words.dropFirst()) { #expect(a.maxX < b.minX, "a space between words") }
        #expect(abs(layout.words[0].minX - 24) < 1, "centered between the paddings")
        #expect(abs(layout.words[2].maxX - (size.width - 24)) < 1)
        #expect(layout.words[1].width < layout.words[0].width, "measured, not counted: “ir” is narrower than “Quero”")
        #expect(PhraseLayout(words, font: font, size: CGSize(width: size.width - 20, height: 56), padding: 24) == nil, "a wrapping phrase is drawn whole")
    }

    @Test func targetsShareTheCapsuleWithoutDeadZones() {
        let targets = Self.layout.targets
        #expect(targets.count == 3)
        for (a, b) in zip(targets, targets.dropFirst()) { #expect(a.maxX == b.minX, "no gap and no overlap") }
        #expect(targets.allSatisfy { $0.minY == 0 && $0.height == 56 }, "the capsule's full height")
        #expect(targets.first!.minX <= 0 && targets.last!.maxX >= 146, "the ends reach the capsule's edges")
    }

    @Test func aShortWordGetsAFullTarget() {
        let targets = Self.layout.targets
        #expect(targets.allSatisfy { $0.width >= PhraseLayout.minTarget - 0.001 })
        // “e” takes all it lacks from “Quero”: “ir” has no 44 pt to spare.
        #expect(targets[1].minX == 59 && targets[1].maxX == 103)
        #expect(targets[0].width >= PhraseLayout.minTarget)
        // “ir”, last, reaches out of the capsule rather than taking from “e”.
        #expect(targets[2].minX == 103 && targets[2].maxX == 147)
    }

    @Test func boundariesFallHalfwayBetweenWords() {
        let wide = PhraseLayout(words: [CGRect(x: 24, y: 16, width: 60, height: 24), CGRect(x: 90, y: 16, width: 60, height: 24)],
                                size: CGSize(width: 174, height: 56))
        #expect(wide.targets[0].maxX == 87)
        #expect(wide.gapX(0) == 24 && wide.gapX(1) == 87 && wide.gapX(2) == 150)
    }

    @Test func theGapIsTheNearestOneAndOutsideTheCapsuleItsEnds() {
        let layout = Self.layout
        #expect(layout.gap(at: -40) == 0)
        #expect(layout.gap(at: 40) == 0, "left half of “Quero”")
        #expect(layout.gap(at: 70) == 1, "right half of “Quero”")
        #expect(layout.gap(at: 118) == 3, "right half of “ir”")
        #expect(layout.gap(at: 400) == 3)
    }

    @Test func hysteresisHoldsTheGapNearABoundary() {
        let layout = Self.layout // boundary between gaps 0 and 1: the middle of “Quero”, x = 54
        #expect(layout.gap(at: 60, current: 0) == 0, "6 pt past the middle is not enough")
        #expect(layout.gap(at: 65, current: 0) == 1, "past the hysteresis it moves")
        #expect(layout.gap(at: 48, current: 1) == 1)
        #expect(layout.gap(at: 43, current: 1) == 0)
        #expect(layout.gap(at: 130, current: 0) == 3, "a fast finger jumps straight to its gap")
    }
}
