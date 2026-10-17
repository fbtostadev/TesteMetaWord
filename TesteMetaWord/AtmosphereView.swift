import SwiftUI
import simd

struct AtmosphereInput: Equatable {
    struct Pair: Equatable {
        let id: MergePair
        let source: CGRect
        let target: CGRect
        let logicalGap: CGFloat
        let distance: Double
        let armed: Bool
        let resistance: Double

        var proximity: Double {
            let depth = 0.45 * min(source.height, target.height)
            return min(1, max(0, (distance - logicalGap) / max(1, distance + depth)))
        }
    }

    let focusID: UUID?
    let focus: CGRect
    let occupied: Set<Int>
    let focusEngaged: Bool
    let pair: Pair?

    var frame: AtmosphereFrame { AtmosphereFrame(input: self) }
}

/// Fixed-size numeric uniforms also form the SwiftUI animation vector. No vocabulary or
/// per-word buffers reach the GPU: only the focus, three zones and the two active surfaces.
struct AtmosphereFrame: VectorArithmetic, Sendable {
    var focus = SIMD4<Double>.zero
    var source = SIMD4<Double>.zero
    var target = SIMD4<Double>.zero
    var zones = SIMD3<Double>.zero
    /// Ring gap of each zone; animates as outer zones close in on the focus.
    var gaps = SIMD3<Double>.zero
    var pairIntensity = 0.0
    var proximity = 0.0
    var pairVisibility = 0.0

    init() {}

    init(input: AtmosphereInput) {
        focus = Self.rectangle(input.focus)
        if input.focus.width > 0 && input.focus.height > 0 {
            gaps = SIMD3((1...3).map { Double(Physics.zoneGap($0, occupied: input.occupied)) })
            zones = SIMD3(input.occupied.contains(1) ? (input.focusEngaged ? 0.085 : 0.06) : 0,
                          input.occupied.contains(2) ? 0.035 : 0,
                          input.occupied.contains(3) ? 0.022 : 0)
        }
        // Seed inactive geometry at the optical center, never at the top-left corner.
        source = focus
        target = focus
        if let pair = input.pair {
            source = Self.rectangle(pair.source)
            target = Self.rectangle(pair.target)
            pairIntensity = (pair.armed ? 0.13 : 0.055) * (1 - min(1, max(0, pair.resistance)) * 0.55)
            proximity = pair.proximity
            pairVisibility = 1
        }
    }

    static func rectangle(_ rect: CGRect) -> SIMD4<Double> {
        SIMD4(rect.midX, rect.midY, max(0, rect.width), max(0, rect.height))
    }

    var shader: Shader {
        var shader = ShaderLibrary.atmosphere(
            .float4(focus.x, focus.y, focus.z, focus.w),
            .float3(zones.x, zones.y, zones.z),
            .float3(gaps.x, gaps.y, gaps.z),
            .float4(source.x, source.y, source.z, source.w),
            .float4(target.x, target.y, target.z, target.w),
            .float(pairIntensity), .float(proximity), .float(pairVisibility))
        shader.dithersColor = true
        return shader
    }

    static var zero: Self { Self() }
    static func + (a: Self, b: Self) -> Self {
        var result = Self()
        result.focus = a.focus + b.focus
        result.source = a.source + b.source
        result.target = a.target + b.target
        result.zones = a.zones + b.zones
        result.gaps = a.gaps + b.gaps
        result.pairIntensity = a.pairIntensity + b.pairIntensity
        result.proximity = a.proximity + b.proximity
        result.pairVisibility = a.pairVisibility + b.pairVisibility
        return result
    }
    static func - (a: Self, b: Self) -> Self {
        var negative = b
        negative.scale(by: -1)
        return a + negative
    }
    mutating func scale(by value: Double) {
        focus *= value
        source *= value
        target *= value
        zones *= value
        gaps *= value
        pairIntensity *= value
        proximity *= value
        pairVisibility *= value
    }
    var magnitudeSquared: Double {
        simd_dot(focus, focus) + simd_dot(source, source) + simd_dot(target, target)
            + simd_dot(zones, zones) + simd_dot(gaps, gaps) + pairIntensity * pairIntensity + proximity * proximity
            + pairVisibility * pairVisibility
    }
}

struct AtmosphereView: View {
    let input: AtmosphereInput
    @State private var lastPair: AtmosphereInput.Pair?
    @State private var lastFocus: CGRect?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var resolvedInput: AtmosphereInput {
        // A fusion replaces the focus before SwiftUI measures its new label. Keep the
        // previous center through that gap so the field never travels toward (0, 0).
        let focus = input.focus.width > 0 && input.focus.height > 0 ? input.focus : (lastFocus ?? input.focus)
        return AtmosphereInput(focusID: input.focusID, focus: focus, occupied: input.occupied,
                               focusEngaged: input.focusEngaged, pair: input.pair)
    }

    private var frame: AtmosphereFrame {
        var frame = resolvedInput.frame
        if input.pair == nil, let lastPair {
            // Fade out at the last valid surfaces, even if fusion has removed the words.
            frame.source = AtmosphereFrame.rectangle(lastPair.source)
            frame.target = AtmosphereFrame.rectangle(lastPair.target)
            frame.proximity = lastPair.proximity
        }
        return frame
    }

    var body: some View {
        MetalAtmosphere(frame: frame)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: input.focusID)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: input.occupied)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: input.focus.size)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: input.focusEngaged)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: input.pair?.id)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: input.pair?.armed)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: input.pair?.resistance)
        .transaction { if reduceMotion { $0.animation = nil } }
        .onChange(of: input.pair, initial: true) { _, pair in
            if let pair { lastPair = pair }
        }
        .onChange(of: input.focus, initial: true) { _, focus in
            if focus.width > 0 && focus.height > 0 { lastFocus = focus }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private nonisolated struct MetalAtmosphere: View, Animatable {
    var frame: AtmosphereFrame
    var animatableData: AtmosphereFrame {
        get { frame }
        set { frame = newValue }
    }
    var body: some View { Rectangle().fill(frame.shader) }
}
