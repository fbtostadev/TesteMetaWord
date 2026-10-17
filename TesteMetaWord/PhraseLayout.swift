import UIKit

/// The words of a phrase on one line inside its capsule, framed by the text layout itself, and
/// the targets that share the capsule among them: the gap a dropped word enters, and (for taking a
/// word out later) each word's own target.
struct PhraseLayout: Equatable {
    /// Each word's glyph frame, in the capsule's coordinates (origin at its top-left corner).
    let words: [CGRect]
    let size: CGSize

    /// Smallest target, in points, for a word taken from the phrase (alternative communication).
    static let minTarget: CGFloat = 44
    /// How far past the middle of a word the finger must go before the gap changes side.
    static let hysteresis: CGFloat = 10

    init(words: [CGRect], size: CGSize) {
        self.words = words
        self.size = size
    }

    /// Lays `words` out with TextKit, joined by spaces as the capsule draws them, centered in a
    /// capsule of `size`. Nil when the phrase does not fit on one line between the capsule's
    /// horizontal `padding`: the capsule then wraps it as one text.
    init?(_ words: [String], font: UIFont, size: CGSize, padding: CGFloat) {
        guard !words.isEmpty else { return nil }
        let text = words.joined(separator: " ")
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let used = layout.usedRect(for: container)
        guard used.width <= size.width - 2 * padding + 1 else { return nil }
        let origin = CGPoint(x: (size.width - used.width) / 2, y: (size.height - used.height) / 2)
        var location = 0
        var frames: [CGRect] = []
        for word in words {
            let range = NSRange(location: location, length: (word as NSString).length)
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            frames.append(layout.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y))
            location += range.length + 1
        }
        self.init(words: frames, size: size)
    }

    /// Gap `k` lies before word `k` (0 … `words.count`). The boundary between two gaps is the
    /// middle of the word between them, so a finger anywhere picks the nearest gap, and left or right
    /// of the capsule picks its ends. Once a gap is chosen, it changes only when the finger is
    /// `hysteresis` past the boundary, so the phrase does not flicker as it opens.
    func gap(at x: CGFloat, current: Int? = nil) -> Int {
        let middles = words.map(\.midX)
        guard let current else { return middles.count { $0 < x } }
        let right = middles.count { $0 < x - Self.hysteresis }
        let left = middles.count { $0 < x + Self.hysteresis }
        if right > current { return right }
        if left < current { return left }
        return current
    }

    /// Where gap `k` sits: halfway across the space between its words, or the phrase's ends.
    func gapX(_ k: Int) -> CGFloat {
        guard let first = words.first, let last = words.last else { return size.width / 2 }
        if k <= 0 { return first.minX }
        if k >= words.count { return last.maxX }
        return (words[k - 1].maxX + words[k].minX) / 2
    }

    /// Each word's target: the capsule shared with no dead zones, every boundary halfway across
    /// the space between neighbours, at the capsule's full height. A word narrower than
    /// `minTarget` takes the difference from its neighbours (never leaving one below it), and the
    /// words at the ends reach out of the capsule when they need more.
    var targets: [CGRect] {
        guard !words.isEmpty else { return [] }
        var bounds = [0] + zip(words, words.dropFirst()).map { ($0.maxX + $1.minX) / 2 } + [size.width]
        let n = words.count
        func width(_ i: Int) -> CGFloat { bounds[i + 1] - bounds[i] }
        for i in 0..<n where width(i) < Self.minTarget {
            var missing = Self.minTarget - width(i)
            let half = missing / 2
            // Half from each side, then whatever one side could not give from the other.
            for (pass, left) in [true, false, true, false].enumerated() where missing > 0 {
                let want = pass < 2 ? min(half, missing) : missing
                let neighbour = left ? i - 1 : i + 1
                let spare = neighbour < 0 || neighbour >= n ? want : max(0, width(neighbour) - Self.minTarget)
                let take = min(want, spare)
                if left { bounds[i] -= take } else { bounds[i + 1] += take }
                missing -= take
            }
        }
        let height = max(size.height, Self.minTarget)
        return (0..<n).map { CGRect(x: bounds[$0], y: (size.height - height) / 2, width: width($0), height: height) }
    }
}
