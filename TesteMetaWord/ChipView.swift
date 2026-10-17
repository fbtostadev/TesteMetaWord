import SwiftUI

/// A gap the phrase opens for a word about to enter it: before word `gap`, `width` wide.
struct Opening: Equatable {
    let gap: Int
    let width: CGFloat
}

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
    /// The BubbleKey draws its phrase word by word, so a gap can open between two words.
    var phrase: (words: [String], layout: PhraseLayout)?
    var opening: Opening?
    /// Where the prepared word would enter ("no início", "depois de quero", "no fim").
    var insertion: String?
    /// VoiceOver's adjustable action moves the gap by one word.
    var adjust: ((Int) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var font: Font {
        .system(size: UIFontMetrics(forTextStyle: .title3).scaledValue(for: 20) * chip.scale, weight: .semibold)
    }

    var body: some View {
        Button(action: activate) {
            label.contentShape(Capsule())
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
        .modifier(Adjustable(adjust: adjust))
        .accessibilityLabel(chip.text)
        .accessibilityValue([armed ? "Pronto para combinar" : selected ? "Selecionado" : "", insertion.map { "inserir " + $0 } ?? ""]
            .filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityHint(armed ? "Ative para confirmar a combinação" : "Selecione e depois escolha outra palavra")
        .accessibilityAddTraits(selected || armed ? .isSelected : [])
        .accessibilityActions {
            Button("Derivar palavras relacionadas", action: derive)
            if canUndo { Button("Desfazer última combinação", action: undo) }
        }
        .accessibilityIdentifier("chip-\(chip.text)")
    }

    /// One text, or the phrase word by word at the frames the text layout gave them. An opening
    /// widens the capsule and moves the words after the gap aside; the words before it stay.
    @ViewBuilder private var label: some View {
        if let phrase, phrase.words.count == phrase.layout.words.count {
            let open = opening?.width ?? 0
            ZStack(alignment: .topLeading) {
                ForEach(phrase.words.indices, id: \.self) { i in
                    Text(phrase.words[i])
                        .font(font)
                        .foregroundStyle(.black)
                        .fixedSize()
                        .position(x: phrase.layout.words[i].midX + (i < (opening?.gap ?? 0) ? 0 : open), y: size.height / 2)
                }
            }
            .frame(width: size.width + open, height: size.height)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82), value: opening)
        } else {
            Text(chip.text)
                .font(font)
                .multilineTextAlignment(.center)
                .foregroundStyle(.black)
                .padding(.horizontal, 24 * chip.scale)
                .frame(width: size.width, height: size.height)
        }
    }
}

/// Swiping up or down moves the gap; only while there is one to move.
private struct Adjustable: ViewModifier {
    let adjust: ((Int) -> Void)?

    func body(content: Content) -> some View {
        if let adjust {
            content.accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: adjust(1)
                case .decrement: adjust(-1)
                @unknown default: break
                }
            }
        } else {
            content
        }
    }
}
