import Testing
import Foundation
import CoreGraphics
@testable import TesteMetaWord

@MainActor struct PinchTests {
    @Test func convergingPinchArmsAndReleaseConfirmsTheFusion() {
        let c = Composition()
        let a = c.chips[0].id, b = c.chips[1].id // querer, ir
        c.beginPinch(a, b)
        #expect(c.activePair == MergePair(source: a, target: b))
        c.updatePinch(penetration: 0.45, time: 0)
        #expect(c.dropCandidate == MergePair(source: a, target: b))
        #expect(c.endPinch() == MergePair(source: a, target: b))
        #expect(c.pinching == nil && c.dropCandidate == nil)
        c.tap(a) // the view confirms the candidate after the convergence
        #expect(c.chips.map(\.text).contains("Quero ir"))
        #expect(c.chips.map(\.text).contains("agora"))
    }

    @Test func releasingBelowTheThresholdChangesNothing() {
        let c = Composition()
        let original = c.chips
        c.beginPinch(original[0].id, original[1].id)
        c.updatePinch(penetration: 0.44, time: 0)
        #expect(c.dropCandidate == nil)
        #expect(c.endPinch() == nil)
        #expect(c.candidate == nil)
        #expect(c.chips == original)
        #expect(!c.canUndo)
    }

    @Test func spreadingTheFingersAfterArmingDisarms() {
        let c = Composition()
        c.beginPinch(c.chips[0].id, c.chips[1].id)
        c.updatePinch(penetration: 0.5, time: 0)
        #expect(c.dropCandidate != nil)
        c.updatePinch(penetration: 0.2, time: 0.1)
        #expect(c.dropCandidate == nil)
        #expect(c.endPinch() == nil)
    }

    @Test func incompatiblePairNeverArmsButTheMembraneResists() {
        let c = Composition()
        let a = c.chips[4].id, b = c.chips[5].id // eu, brincar
        c.beginPinch(a, b)
        c.updatePinch(penetration: -0.2, time: 0)
        #expect(c.resistance == 0)
        c.updatePinch(penetration: 0.9, time: 0.1)
        #expect(c.dropCandidate == nil)
        #expect(c.resistance > 0)
        #expect(c.activePair == MergePair(source: a, target: b))
        #expect(c.endPinch() == nil)
    }

    @Test func pinchReplacesATapSelectionAndADrag() {
        let c = Composition()
        let a = c.chips[0].id, b = c.chips[1].id
        c.tap(a)
        c.tap(b)
        #expect(c.candidate != nil)
        c.beginPinch(a, b)
        #expect(c.candidate == nil && c.selected == nil)
        c.beginDrag(a)
        #expect(c.pinching == nil)
    }

    @Test func aTouchPicksTheChipUnderIt() {
        let a = UUID(), b = UUID()
        let centers = [a: CGPoint(x: 100, y: 100), b: CGPoint(x: 180, y: 100)]
        let sizes = [a: CGSize(width: 100, height: 56), b: CGSize(width: 100, height: 56)]
        #expect(Physics.hit(CGPoint(x: 70, y: 110), centers: centers, sizes: sizes) == a)
        #expect(Physics.hit(CGPoint(x: 215, y: 90), centers: centers, sizes: sizes) == b)
        #expect(Physics.hit(CGPoint(x: 135, y: 100), centers: centers, sizes: sizes) == a) // overlap: nearest center
        #expect(Physics.hit(CGPoint(x: 400, y: 400), centers: centers, sizes: sizes) == nil)
    }

    @Test func rejectingOnlyWhileAnIncompatiblePinchTouches() {
        let c = Composition()
        c.beginPinch(c.chips[4].id, c.chips[5].id) // eu, brincar
        #expect(!c.rejecting)
        c.updatePinch(penetration: 0.9, time: 0.1)
        #expect(c.rejecting)
        c.updatePinch(penetration: nil, time: 0.2)
        #expect(!c.rejecting)
        let ok = Composition()
        ok.beginPinch(ok.chips[0].id, ok.chips[1].id)
        ok.updatePinch(penetration: 0.3, time: 0)
        #expect(!ok.rejecting)
    }

    @Test func approachTargetFollowsACompatibleNeighbourAndClearsOnCancel() {
        let c = Composition()
        let a = c.chips[0].id, b = c.chips[1].id
        c.beginDrag(a)
        c.updateProximity(target: b, penetration: 0.1, time: 0)
        #expect(c.approachTarget == b)
        c.updateProximity(target: nil, penetration: 0, time: 0.1)
        #expect(c.approachTarget == nil)
        c.updateProximity(target: b, penetration: 0.1, time: 0.2)
        c.cancel()
        #expect(c.approachTarget == nil)
    }
}
