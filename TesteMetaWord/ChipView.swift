import SwiftUI

struct ChipView: View {
    let chip: WordChip
    let size: CGSize
    let selected: Bool
    /// Deep overlap (drag) or tap-prepared pair: confirming now would fuse.
    let armed: Bool
    let canUndo: Bool
    let namespace: Namespace.ID
    let activate: () -> Void
    let undo: () -> Void
    /// Buds related words, as shaking the bubble does.
    let derive: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: activate) {
            Text(chip.text)
                .font(.system(size: UIFontMetrics(forTextStyle: .title3).scaledValue(for: 20) * chip.scale, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.black)
                .padding(.horizontal, 24 * chip.scale)
                .frame(width: size.width, height: size.height)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(.white.opacity(armed ? 1 : 0.92)).interactive(), in: .capsule)
        .glassEffectID(chip.glassID, in: namespace)
        .overlay {
            Capsule().strokeBorder(armed ? Color.white : selected ? Color.cyan : .clear, lineWidth: 3)
                .shadow(color: .white.opacity(armed ? 0.8 : 0), radius: 10)
                .allowsHitTesting(false)
        }
        .keyframeAnimator(initialValue: 1.0, trigger: armed) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            if armed && !reduceMotion {
                CubicKeyframe(1.05, duration: 0.09)
                SpringKeyframe(1.0, duration: 0.26, spring: .bouncy)
            } else {
                LinearKeyframe(1.0, duration: 0.01)
            }
        }
        .sensoryFeedback(.alignment, trigger: armed) { _, isArmed in isArmed }
        .accessibilityLabel(chip.text)
        .accessibilityValue(armed ? "Pronto para combinar" : selected ? "Selecionado" : "")
        .accessibilityHint(armed ? "Ative para confirmar a combinação" : "Selecione e depois escolha outra palavra")
        .accessibilityAddTraits(selected || armed ? .isSelected : [])
        .accessibilityActions {
            Button("Derivar palavras relacionadas", action: derive)
            if canUndo { Button("Desfazer última combinação", action: undo) }
        }
        .accessibilityIdentifier("chip-\(chip.text)")
    }
}
