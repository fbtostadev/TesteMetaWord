import SwiftUI
import UIKit

struct ContentView: View {
    @State private var composition = Composition()
    @State private var bodies: [UUID: Physics.Body] = [:]
    /// Each word's cell in the honeycomb, the rows it lies on, and the canvas and sizes it was
    /// made for. Changes are local; only a new canvas or a taller word lays it out again.
    @State private var layout: [UUID: CGPoint] = [:]
    @State private var grid: Physics.Grid?
    @State private var layoutCanvas = CGSize.zero
    @State private var layoutSizes: [UUID: CGSize] = [:]
    @State private var lastTick: Date?
    @State private var dragOrigin: CGPoint?
    /// The dragging finger, which picks the BubbleKey's gap.
    @State private var dragFinger: CGPoint?
    /// 0 … 1: how much the BubbleKey stands out while a dragged word is over it (it grows
    /// slightly and the words around it step aside), eased in and out on the frame clock.
    @State private var emphasis: CGFloat = 0
    @State private var fusionTask: Task<Void, Never>?
    @State private var fusingPair: MergePair?
    @State private var passiveTask: Task<Void, Never>?
    /// Idle watchdog: since when the physics has been held with no finger on the screen, and
    /// whether a waiting tap selection has stopped holding it.
    @State private var heldSince: TimeInterval?
    @State private var selectionReleased = false
    @State private var showCalibration = false
    /// The atmosphere shader draws once it has compiled; without it the canvas stays plain.
    @State private var metalReady = false
    @State private var ignoreTapUntil = Date.distantPast
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var fontSize = 20.0
    @State private var splitSound = SplitSound()
    @State private var sfx = Sfx()
    /// The master bubble under a long press that will split it, and when the press began.
    @State private var tension: (id: UUID, start: TimeInterval)?
    @GestureState private var pressing: UUID?
    /// Fingers on the canvas in window coordinates, from `TouchTracker`.
    @State private var touches: [ObjectIdentifier: CGPoint] = [:]
    @State private var canvasOrigin = CGPoint.zero
    @State private var pinch: Pinch?
    /// Chips whose finger outlived a pinch; ignored until every finger lifts.
    @State private var suppressed: Set<UUID> = []
    @State private var shake = ShakeDetector()
    /// When the first finger of the current touch went down, and the word it pulled out of the
    /// BubbleKey's phrase, which the rest of that drag moves.
    @State private var touchDown: TimeInterval?
    @State private var lifted: UUID?

    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82) }
    /// Births and removals: a quick spring for the budding, a plain dissolve with Reduce Motion.
    private var birth: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.7) }

    /// Canvas geometry and measured chip sizes for one layout pass.
    struct Space {
        let sizes: [UUID: CGSize]
        let canvas: CGSize
        var bounds: CGRect { CGRect(origin: .zero, size: canvas).insetBy(dx: 16, dy: 16) }
        var center: CGPoint { CGPoint(x: canvas.width / 2, y: canvas.height / 2) }
    }

    /// What the honeycomb depends on; any change reorders it.
    struct LayoutInputs: Equatable {
        let chips: [UUID]
        let zones: [UUID: Int]
        let focus: UUID?
        let sizes: [UUID: CGSize]
        let canvas: CGSize
    }

    /// One finger on each of two chips: which finger holds which chip, and where both started.
    struct Pinch {
        let fingers: [ObjectIdentifier: UUID]
        let touchStart: [ObjectIdentifier: CGPoint]
        let chipStart: [UUID: CGPoint]
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(160, geometry.size.width)
            let sizes = Dictionary(uniqueKeysWithValues: composition.chips.map { ($0.id, measure($0, width: width)) })
            let space = Space(sizes: sizes, canvas: CGSize(width: width, height: canvasHeight(sizes, width: width, viewport: max(300, geometry.size.height - 150))))
            VStack(spacing: 0) {
                toolbar(space)
                ScrollView {
                    TimelineView(.animation(paused: showCalibration || (reduceMotion && composition.dragging == nil && composition.pinching == nil))) { context in
                        canvas(space, time: context.date.timeIntervalSinceReferenceDate)
                            .onChange(of: context.date) { _, date in tick(date, space) }
                    }
                }
                .scrollDisabled(composition.dragging != nil || composition.pinching != nil)
                status(space)
                    .frame(minHeight: 66)
                    .padding(.horizontal, 24)
            }
            .background {
                Button("Cancelar seleção") { cancel(space) }
                    .keyboardShortcut(.cancelAction)
                    .hidden()
                    .accessibilityHidden(true)
                // The arrows move the gap of a prepared pair that holds the BubbleKey.
                if composition.candidate.flatMap(composition.entering) != nil, fusingPair == nil {
                    ForEach([(-1, KeyEquivalent.leftArrow), (1, .rightArrow)], id: \.0) { step, key in
                        Button(step < 0 ? "Inserir antes" : "Inserir depois") {
                            withAnimation(motion) { composition.moveInsertion(by: step) }
                        }
                        .keyboardShortcut(key, modifiers: [])
                        .hidden()
                        .accessibilityHidden(true)
                    }
                }
            }
            .onChange(of: geometry.size, initial: true) {
                cancel(space)
                if bodies.isEmpty, let first = composition.chips.first {
                    bodies = Physics.spawn(composition.chips.map(\.id), core: nil, at: space.center, seed: first.id)
                    settleIfReduced(space)
                }
            }
            .onChange(of: LayoutInputs(chips: composition.chips.map(\.id), zones: composition.zones, focus: composition.focus, sizes: sizes, canvas: space.canvas), initial: true) {
                relayout(space)
            }
            .onChange(of: dynamicTypeSize) { cancel(space) }
            .onChange(of: composition.calibration) { cancel(space) }
        }
        .background {
            GeometryReader { geometry in
                let focusHeight = composition.chips.first { $0.id == composition.focus }
                    .map { measure($0, width: max(160, geometry.size.width)).height } ?? 56
                ZStack {
                    RadialGradient(
                        colors: [Color(red: 0.055, green: 0.068, blue: 0.095), Color(red: 0.025, green: 0.032, blue: 0.05)],
                        center: .center, startRadius: 0,
                        endRadius: max(geometry.size.width, geometry.size.height) * 0.7
                    )
                    // Extend the canvas vignette behind the chrome to avoid a rectangular seam.
                    RadialGradient(
                        colors: [.clear, .black.opacity(0.3)], center: .center,
                        startRadius: focusHeight / 2 + Physics.zoneGap(3) + 68,
                        endRadius: max(focusHeight / 2 + Physics.zoneGap(3) + 220,
                                       hypot(geometry.size.width, geometry.size.height) / 2)
                    )
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: focusHeight)
                .transaction { if reduceMotion { $0.animation = nil } }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .preferredColorScheme(.dark)
        .task {
            await composition.refresh()
            metalReady = (try? await AtmosphereFrame.zero.shader.compile(as: .shapeStyle)) != nil
        }
        .onDisappear { fusionTask?.cancel() }
    }

    private func canvas(_ space: Space, time: TimeInterval) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
                .onTapGesture { cancel(space) }
                .accessibilityHidden(true)
            if metalReady {
                AtmosphereView(input: atmosphereInput(space, time: time))
            }
            GlassEffectContainer(spacing: Physics.glassSpacing) {
                ZStack(alignment: .topLeading) {
                    ForEach(composition.chips) { chip in
                        ChipView(
                            chip: chip, size: space.sizes[chip.id] ?? .zero,
                            selected: composition.selected == chip.id || composition.activePair?.contains(chip.id) == true,
                            armed: composition.dropCandidate?.contains(chip.id) == true || composition.candidate?.contains(chip.id) == true,
                            canUndo: composition.splittable == chip.id,
                            namespace: glass,
                            activate: { activate(chip.id, space) },
                            undo: { undo(chip.id, space) },
                            derive: { derive(chip.id, space) },
                            remove: { index in takeOut(index, of: chip, space) },
                            phrase: phrase(chip, space).flatMap { layout in composition.focusPhrase.map { ($0, layout) } },
                            opening: opening(chip, space),
                            insertion: insertionValue(chip),
                            adjust: voiceOver && insertionValue(chip) != nil ? { step in composition.moveInsertion(by: step) } : nil
                        )
                        .overlay {
                            Capsule().strokeBorder(.white.opacity(composition.dragging == chip.id || composition.pinching?.contains(chip.id) == true ? composition.resistance * 0.85 : 0), lineWidth: 2)
                                .allowsHitTesting(false)
                        }
                        .offset(membraneOffset(chip, space, time: time))
                        .offset(tensionProgress(chip, time: time).map { SplitTension.offset(progress: $0, time: time) } ?? .zero)
                        .scaleEffect((tensionProgress(chip, time: time).map(SplitTension.scale) ?? 1) * focusScale(chip))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: composition.resistance)
                        .position(rendered(chip, space, time: time))
                        .zIndex(composition.dragging == chip.id || composition.pinching?.contains(chip.id) == true || fusingPair?.source == chip.id ? 1 : 0)
                        .transition(transition(for: chip))
                        .simultaneousGesture(drag(chip.id, space))
                        .simultaneousGesture(LongPressGesture(minimumDuration: SplitTension.duration)
                            .updating($pressing) { isPressing, state, _ in if isPressing { state = chip.id } }
                            .onEnded { _ in
                                guard canSplit(chip.id) else { return }
                                ignoreTapUntil = Date().addingTimeInterval(0.4)
                                splitSound.burst()
                                undo(chip.id, space, quiet: true)
                            })
                    }
                }
            }
        }
        .frame(width: space.canvas.width, height: space.canvas.height)
        .coordinateSpace(name: "canvas")
        .gesture(TouchTracker { touches = $0 })
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { canvasOrigin = $0 }
        .onChange(of: touches) { old, new in
            if old.isEmpty, !new.isEmpty { touchDown = Date().timeIntervalSinceReferenceDate }
            trackPinch(space)
        }
        // The passage over the BubbleKey's gaps plays the drag's scale, one degree per gap.
        .onChange(of: composition.insertion) { old, new in
            if composition.dragging != nil, let new, new != old { sfx.pass(degree: new) }
        }
        .onChange(of: composition.rejecting) { _, rejecting in
            if rejecting { sfx.play(.error) }
        }
        .onChange(of: pressing) { _, id in
            if let id, canSplit(id) {
                tension = (id, Date().timeIntervalSinceReferenceDate)
                splitSound.begin()
            } else if tension != nil {
                tension = nil
                splitSound.cancel()
            }
        }
    }

    /// Only the latest result divides, never in the middle of another act or with two fingers down.
    private func canSplit(_ id: UUID) -> Bool {
        fusingPair == nil && composition.dragging == nil && composition.pinching == nil
            && touches.count <= 1 && !suppressed.contains(id) && composition.splittable == id
    }

    /// Long-press tension on the master bubble. No tremor with Reduce Motion; the sound remains.
    private func tensionProgress(_ chip: WordChip, time: TimeInterval) -> Double? {
        guard !reduceMotion, let tension, tension.id == chip.id else { return nil }
        return SplitTension.progress(since: tension.start, now: time)
    }

    /// The shader's snapshot. Geometry follows the visible surfaces;
    /// proximity still follows the logical distance used by the gesture, before membrane recoil.
    private func atmosphereInput(_ space: Space, time: TimeInterval) -> AtmosphereInput {
        let focus = composition.focus
        let open = composition.chips.first { $0.id == focus }.flatMap { opening($0, space) }?.width ?? 0
        let focusRect = focus.flatMap { id in
            bodies[id].flatMap { body in space.sizes[id].map { size in
                let scale = composition.chips.first { $0.id == id }.map(focusScale) ?? 1
                return Physics.rect(body.position, CGSize(width: (size.width + open) * scale, height: size.height * scale))
            } }
        } ?? .zero
        let engaged = focus.map { id in
            composition.dragging == id || composition.selected == id
                || composition.activePair?.contains(id) == true || fusingPair?.contains(id) == true
        } ?? false
        var pair: AtmosphereInput.Pair?
        if let active = composition.activePair,
           let source = composition.chips.first(where: { $0.id == active.source }),
           let target = composition.chips.first(where: { $0.id == active.target }),
           let sourceSize = space.sizes[source.id], let targetSize = space.sizes[target.id],
           let logicalSource = bodies[source.id]?.position {
            func visibleRect(_ chip: WordChip, _ size: CGSize) -> CGRect {
                let point = rendered(chip, space, time: time)
                let offset = membraneOffset(chip, space, time: time)
                return Physics.rect(CGPoint(x: point.x + offset.width, y: point.y + offset.height), size)
            }
            let logicalGap = Physics.signedDistance(
                Physics.rect(logicalSource, sourceSize),
                Physics.rect(rendered(target, space, time: time), targetSize))
            pair = AtmosphereInput.Pair(
                id: active, source: visibleRect(source, sourceSize), target: visibleRect(target, targetSize),
                logicalGap: logicalGap, distance: composition.calibration.distance,
                armed: composition.dropCandidate != nil || composition.candidate != nil,
                resistance: composition.resistance)
        }
        return AtmosphereInput(focusID: focus, focus: focusRect,
                               occupied: Set(composition.zones.values), focusEngaged: engaged, pair: pair)
    }

    private func toolbar(_ space: Space) -> some View {
        HStack {
            Button { undo(nil, space) } label: {
                Image(systemName: "chevron.left").frame(width: 48, height: 48)
            }
            .buttonStyle(.glass)
            .disabled(!composition.canUndo)
            .accessibilityLabel("Desfazer")
            .keyboardShortcut("z", modifiers: .command)
            Spacer()
            Text("Palavras").font(.headline).foregroundStyle(.white.opacity(0.8))
            Spacer()
            Button {
                cancel(space)
                showCalibration = true
            } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 48, height: 48)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Calibração")
            .popover(isPresented: $showCalibration) { calibrationPanel }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var statusText: String {
        if fusingPair != nil { return "Combinando…" }
        if composition.dropCandidate != nil { return "Solte para combinar." }
        if composition.pinching != nil { return "Aproxime as duas palavras." }
        if composition.candidate != nil { return "Toque em uma das duas palavras para combinar." }
        if composition.activePair != nil { return "Avance até sobrepor as duas palavras." }
        if composition.selected != nil { return "Escolha outra palavra para combinar." }
        return "Sobreponha duas palavras e solte, ou toque em uma e depois na outra."
    }

    private func status(_ space: Space) -> some View {
        VStack(spacing: 6) {
            Text(statusText).contentTransition(.opacity)
            if composition.candidate != nil, composition.dragging == nil, fusingPair == nil {
                Button("Cancelar") { cancel(space) }.buttonStyle(.borderless)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: statusText)
        .font(.callout)
        .foregroundStyle(.white.opacity(0.85))
        .multilineTextAlignment(.center)
    }

    private var calibrationPanel: some View {
        @Bindable var state = composition
        return VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Calibração").font(.title2.bold())
                Spacer()
                Button("OK") { showCalibration = false }
            }
            Text("Distância: \(Int(state.calibration.distance)) pt")
            Slider(value: $state.calibration.distance, in: 8...60, step: 1) { Text("Distância") }
            Button("Restaurar valores") { state.calibration = Calibration() }
        }
        .padding(24)
        .frame(idealWidth: 360)
        .presentationCompactAdaptation(.sheet)
    }

    private func measure(_ chip: WordChip, width: CGFloat) -> CGSize {
        let text = chip.text
        let scale = chip.scale
        let padding = 48 * scale
        let font = UIFont.systemFont(ofSize: fontSize * scale, weight: .semibold)
        let maxWidth = max(80, width - 80)
        let natural = (text as NSString).size(withAttributes: [.font: font]).width + padding
        let chipWidth = min(maxWidth, max(88 * scale, ceil(natural)))
        let bounds = (text as NSString).boundingRect(with: CGSize(width: chipWidth - padding, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
        return CGSize(width: chipWidth, height: max(56 * scale, ceil(bounds.height) + 28 * scale))
    }

    private func font(_ chip: WordChip) -> UIFont {
        UIFont.systemFont(ofSize: fontSize * chip.scale, weight: .semibold)
    }

    /// The BubbleKey's words as the text layout frames them in its capsule, once the engine has
    /// read its phrase; nil for other words and for a phrase that wraps.
    private func phrase(_ chip: WordChip, _ space: Space) -> PhraseLayout? {
        guard chip.id == composition.focus, let words = composition.focusPhrase, let size = space.sizes[chip.id] else { return nil }
        return PhraseLayout(words, font: font(chip), size: size, padding: 24 * chip.scale)
    }

    /// The gap the BubbleKey opens for the word about to enter it: as wide as that word and a
    /// space, opening with the overlap until the pair arms.
    private func opening(_ chip: WordChip, _ space: Space) -> Opening? {
        guard chip.id == composition.focus, let gap = composition.insertion, let pair = composition.activePair,
              let word = composition.entering(pair), phrase(chip, space) != nil else { return nil }
        let width = ((word.text + " ") as NSString).size(withAttributes: [.font: font(chip)]).width
        let armed = composition.dropCandidate != nil || composition.candidate != nil
        return Opening(gap: gap, width: ceil(width) * (armed ? 1 : min(1, composition.depth / 0.45)))
    }

    /// Where a prepared word would enter the BubbleKey, for VoiceOver.
    private func insertionValue(_ chip: WordChip) -> String? {
        guard chip.id == composition.focus, let gap = composition.insertion, let words = composition.focusPhrase,
              let pair = composition.candidate, composition.entering(pair) != nil else { return nil }
        if gap == 0 { return "no início" }
        if gap >= words.count { return "no fim" }
        return "depois de " + words[gap - 1].trimmingCharacters(in: [","])
    }

    /// Grows the canvas when large text needs more room than the viewport.
    private func canvasHeight(_ sizes: [UUID: CGSize], width: CGFloat, viewport: CGFloat) -> CGFloat {
        let area = sizes.values.reduce(0) { $0 + ($1.width + Physics.restGap) * ($1.height + Physics.restGap) }
        return max(viewport, area / max(1, width - 32) * 1.5 + 32)
    }

    // MARK: - Physics and idle float

    /// Body position plus the idle orbit. Words being handled stop floating so they hold still.
    private func rendered(_ chip: WordChip, _ space: Space, time: TimeInterval) -> CGPoint {
        var position = bodies[chip.id]?.position ?? space.center
        let way = makeWay(chip, space)
        position.x += way.dx
        position.y += way.dy
        let floats = !reduceMotion && composition.dragging != chip.id && composition.selected != chip.id
            && composition.activePair?.contains(chip.id) != true && fusingPair?.contains(chip.id) != true
            && tension?.id != chip.id
        let orbit = Physics.orbit(phase: chip.phase, time: time, amplitude: floats ? Physics.orbitAmplitude : 0)
        return CGPoint(x: position.x + orbit.dx, y: position.y + orbit.dy)
    }

    // MARK: - BubbleKey in focus

    /// How much the BubbleKey grows at full emphasis.
    private static let focusGrowth: CGFloat = 0.06
    /// Time constant of the emphasis easing.
    private static let emphasisEase: TimeInterval = 0.12

    /// A word dragged within reach of the BubbleKey, until it has entered it, gives the BubbleKey
    /// the stage. Not with Reduce Motion, which moves nothing aside.
    private var emphasisTarget: CGFloat {
        guard !reduceMotion, let focus = composition.focus else { return 0 }
        let over = composition.dragging != nil && composition.approachTarget == focus
        let entering = fusingPair?.contains(focus) == true && composition.candidate.flatMap(composition.entering) != nil
        return over || entering ? 1 : 0
    }

    private func focusScale(_ chip: WordChip) -> CGFloat {
        chip.id == composition.focus ? 1 + Self.focusGrowth * emphasis : 1
    }

    /// The step aside of a word around the emphasized BubbleKey: every word but the BubbleKey and
    /// the pair being handled, away from its grown capsule (scale and open gap).
    private func makeWay(_ chip: WordChip, _ space: Space) -> CGVector {
        guard emphasis > 0.001, let focusID = composition.focus, chip.id != focusID,
              composition.dragging != chip.id, fusingPair?.contains(chip.id) != true,
              let focus = composition.chips.first(where: { $0.id == focusID }),
              let center = bodies[focusID]?.position, let size = space.sizes[focusID],
              let position = bodies[chip.id]?.position, let chipSize = space.sizes[chip.id] else { return .zero }
        let scale = focusScale(focus)
        let open = opening(focus, space)?.width ?? 0
        let growth = CGSize(width: (size.width + open) * scale - size.width, height: size.height * (scale - 1))
        return Physics.makeWay(position, size: chipSize, from: Physics.rect(center, size), growth: growth, emphasis: emphasis)
    }

    /// Fusion results cross-fade into place; every other new word buds out from a smaller scale.
    private func transition(for chip: WordChip) -> AnyTransition {
        if reduceMotion || chip.fusionCount > 0 { return .opacity }
        return .asymmetric(insertion: .scale(scale: 0.4).combined(with: .opacity), removal: .opacity)
    }

    /// The composition holds still during the act (drag, selection, prepared pair, fusion);
    /// repulsion and the zones reorganize it only afterwards.
    private var isActing: Bool {
        let waiting = (composition.selected != nil || composition.candidate != nil) && !selectionReleased
        return showCalibration || composition.dragging != nil || waiting || composition.pinching != nil || fusingPair != nil
    }

    /// Acts never leave the composition frozen. With no finger on the screen, an act left half
    /// done (a drag or pinch whose end never arrived, a fusion that never finished) is cleared
    /// after `staleAct`; a tap selection waiting for its partner stops holding the physics after
    /// `selectionHold` and stays selected. Either way the words drift home gently.
    private static let staleAct: TimeInterval = 1.5
    private static let selectionHold: TimeInterval = 4

    private func watchdog(_ now: TimeInterval, _ space: Space) {
        guard isActing, touches.isEmpty, !showCalibration else {
            heldSince = nil
            if composition.selected == nil && composition.candidate == nil { selectionReleased = false }
            return
        }
        let held = now - (heldSince ?? now)
        if heldSince == nil { heldSince = now }
        let stale = composition.dragging != nil || composition.pinching != nil || pinch != nil || fusingPair != nil
        if stale, held > Self.staleAct {
            cancel(space)
            easeHome()
        } else if !stale, held > Self.selectionHold {
            selectionReleased = true
            easeHome()
        }
    }

    /// Every word sets off for home along the ease-in curve of a release.
    private func easeHome() {
        heldSince = nil
        for id in bodies.keys { bodies[id]?.ramp = 0 }
    }

    private func tick(_ date: Date, _ space: Space) {
        defer { lastTick = date }
        let target = emphasisTarget
        if emphasis != target, let lastTick {
            let step = 1 - exp(-date.timeIntervalSince(lastTick) / Self.emphasisEase)
            emphasis = abs(target - emphasis) < 0.002 ? target : emphasis + (target - emphasis) * step
        } else if reduceMotion {
            emphasis = 0
        }
        if composition.dragging != nil { updateProximity(space, time: date.timeIntervalSinceReferenceDate) }
        if composition.pinching != nil { updatePinchProximity(space) }
        watchdog(date.timeIntervalSinceReferenceDate, space)
        guard !reduceMotion, !isActing, let lastTick else { return }
        simulate(space, dt: min(1.0 / 30, date.timeIntervalSince(lastTick)))
    }

    private func simulate(_ space: Space, dt: CGFloat) {
        Physics.step(&bodies, sizes: space.sizes, targets: layout, bounds: space.bounds, dt: dt)
    }

    /// Updates the honeycomb after a change. Locally, words keep their cells; new words (and words
    /// that changed size) settle where they were born, and only their neighbours make way. A new
    /// canvas, or a word taller than the rows, lays the whole honeycomb out again. Words whose cell
    /// moved set off for it gently; complementary words (a strong fusion) attract.
    private func relayout(_ space: Space) {
        let affinity = { (a: UUID, b: UUID) in composition.strength(a, b) == 1 }
        let kept = layout.filter { id, _ in space.sizes[id] != nil && space.sizes[id] == layoutSizes[id] }
        let tallest = space.sizes.values.map(\.height).max() ?? 56
        let next: [UUID: CGPoint]
        if let grid, layoutCanvas == space.canvas, !kept.isEmpty, tallest + Physics.restGap <= grid.rowHeight + 0.5 {
            let births = Dictionary(uniqueKeysWithValues: composition.chips.filter { kept[$0.id] == nil }
                .map { ($0.id, bodies[$0.id]?.position ?? space.center) })
            let adapted = births.isEmpty ? kept : Physics.adapt(cells: kept, births: births, sizes: space.sizes, grid: grid,
                                                                bounds: space.bounds, affinity: affinity)
            // The honeycomb closes around the BubbleKey, from the inside out; the BubbleKey keeps
            // its place and words beyond the gravity's reach stay still.
            let focus = composition.focus
            let compacted = Physics.compact(cells: adapted, sizes: space.sizes, grid: grid,
                                            toward: focus.flatMap { adapted[$0] } ?? grid.origin, fixed: focus, bounds: space.bounds)
            // The BubbleKey returns to the center with the whole honeycomb, as one block.
            let centered = Physics.recenter(cells: compacted, grid: grid, focus: composition.focus, center: space.center)
            self.grid = centered.grid
            next = centered.cells
        } else {
            grid = Physics.Grid(origin: space.center, sizes: space.sizes)
            layoutCanvas = space.canvas
            next = Physics.layout(sizes: space.sizes, focus: composition.focus, zones: composition.zones,
                                  center: space.center, current: bodies.mapValues(\.position), affinity: affinity)
        }
        layoutSizes = space.sizes
        for (id, cell) in next {
            if let old = layout[id], hypot(old.x - cell.x, old.y - cell.y) < 8 { continue }
            bodies[id]?.ramp = 0
        }
        layout = next
    }

    /// Reduce Motion: jump straight to equilibrium instead of animating the physics.
    private func settleIfReduced(_ space: Space) {
        guard reduceMotion, !isActing else { return }
        relayout(space)
        for _ in 0..<240 { simulate(space, dt: 1.0 / 60) }
    }

    /// Runs a composition change and gives each new word a body. New words are born where the
    /// words they replace were: the one inheriting a removed glass identity stays at the core and
    /// the others bud out (fusion → suggestions, undo → the second origin).
    private func apply(_ space: Space, sound: SfxCue? = .split, origin: CGPoint? = nil, _ change: () -> Void) {
        let before = composition.chips
        withAnimation(birth) { change() }
        let after = composition.chips
        let removed = before.filter { old in !after.contains { $0.id == old.id } }
        let added = after.filter { new in !before.contains { $0.id == new.id } }
        // Each caller names its sound: fusion, split (Undo, split, shake) or none (passive fusion,
        // or the long-press burst that already marked the moment).
        if !added.isEmpty, let sound { sfx.play(sound) }
        let core = added.first { new in removed.contains { $0.glassID == new.glassID } }
        let anchor = core.flatMap { core in removed.first { $0.glassID == core.glassID } }
        let removedPositions = removed.compactMap { bodies[$0.id]?.position }
        let centroid = removedPositions.isEmpty ? space.center : CGPoint(
            x: removedPositions.map(\.x).reduce(0, +) / CGFloat(removedPositions.count),
            y: removedPositions.map(\.y).reduce(0, +) / CGFloat(removedPositions.count))
        let origin = origin ?? anchor.flatMap { bodies[$0.id]?.position } ?? centroid
        for chip in removed { bodies[chip.id] = nil }
        if let seed = (core ?? added.first)?.id {
            bodies.merge(Physics.spawn(added.map(\.id), core: core?.id, at: origin, seed: seed)) { $1 }
        }
        settleIfReduced(space)
        Task { await composition.refresh() }
        if !composition.duplicates.isEmpty { passiveFusion(space) }
    }

    // MARK: - Gestures

    private func activate(_ id: UUID, _ space: Space) {
        guard Date() >= ignoreTapUntil, fusingPair == nil, pinch == nil, !suppressed.contains(id) else { return }
        if let pair = composition.candidate, pair.contains(id) {
            confirmCandidate(pair, space)
            return
        }
        selectionReleased = false
        heldSince = nil
        withAnimation(motion) { composition.tap(id) }
        settleIfReduced(space)
    }

    /// Reverse mitosis: both origins converge to their midpoint, then the result is born there.
    /// A word entering the BubbleKey slides into its open gap instead; the BubbleKey holds its
    /// place and the result is born there.
    private func confirmCandidate(_ pair: MergePair, _ space: Space) {
        let into = insertionPoint(pair, space)
        // A word settling into the BubbleKey snaps with its scale instead of the fusion note.
        let sound: SfxCue? = into == nil ? .fusion : nil
        guard !reduceMotion, let a = bodies[pair.source]?.position, let b = bodies[pair.target]?.position else {
            if into != nil { sfx.snap() }
            apply(space, sound: sound, origin: into?.focus) { composition.tap(pair.source) }
            return
        }
        withAnimation(.easeIn(duration: 0.2)) {
            fusingPair = pair
            if let into {
                bodies[into.word] = Physics.Body(position: into.gap)
                bodies[into.focusID] = Physics.Body(position: into.focus)
            } else {
                let center = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                bodies[pair.source] = Physics.Body(position: center)
                bodies[pair.target] = Physics.Body(position: center)
            }
        }
        fusionTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard composition.candidate == pair else { cancel(space); return }
            if into != nil { sfx.snap() }
            apply(space, sound: sound, origin: into?.focus) { composition.tap(pair.source) }
            fusingPair = nil
            fusionTask = nil
        }
    }

    /// For a pair entering the BubbleKey: the entering word, the BubbleKey, and the open gap's
    /// point on the canvas.
    private func insertionPoint(_ pair: MergePair, _ space: Space) -> (word: UUID, focusID: UUID, focus: CGPoint, gap: CGPoint)? {
        guard let word = composition.entering(pair), let gap = composition.insertion,
              let focusID = composition.focus, let chip = composition.chips.first(where: { $0.id == focusID }),
              let focus = bodies[focusID]?.position, let layout = phrase(chip, space) else { return nil }
        let x = focus.x + (layout.gapX(gap) - layout.size.width / 2) * focusScale(chip)
        return (word.id, focusID, focus, CGPoint(x: x, y: focus.y))
    }

    /// While the dragged word is over the BubbleKey, the gap under the finger, measured on the
    /// closed phrase so the opening does not move the gaps it is chosen from.
    private func updateInsertion(_ space: Space, time: TimeInterval) {
        guard let finger = dragFinger, let focus = composition.focus, composition.approachTarget == focus,
              let chip = composition.chips.first(where: { $0.id == focus }), let layout = phrase(chip, space) else {
            composition.updateInsertion(nil)
            return
        }
        let x = (finger.x - rendered(chip, space, time: time).x) / focusScale(chip) + layout.size.width / 2
        composition.updateInsertion(layout.gap(at: x, current: composition.insertion))
    }

    /// How long a finger rests on a word of the BubbleKey's phrase before pulling counts as taking
    /// the word out; moving sooner drags the whole BubbleKey. Holding still divides it instead.
    private static let pickHold: TimeInterval = 0.2

    private func drag(_ id: UUID, _ space: Space) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named("canvas"))
            .onChanged { value in
                guard fusingPair == nil, pinch == nil, !suppressed.contains(id),
                      let chip = composition.chips.first(where: { $0.id == id }) else { return }
                let now = Date().timeIntervalSinceReferenceDate
                if lifted == nil, composition.dragging != id, let index = wordUnderHold(chip, at: value.startLocation, space, time: now) {
                    // The word leaves the phrase and the rest of the drag carries it; a word with a
                    // twin on the canvas has nothing to carry, so the drag ends here.
                    guard let word = takeOut(index, of: chip, space)?.word else {
                        suppressed.insert(id)
                        return
                    }
                    lifted = word
                    dragOrigin = bodies[word]?.position
                    shake = ShakeDetector()
                    sfx.rollScale()
                    composition.beginDrag(word)
                }
                let handled = lifted ?? id
                if composition.dragging != handled {
                    dragOrigin = rendered(chip, space, time: now)
                    shake = ShakeDetector()
                    sfx.rollScale()
                    composition.beginDrag(handled)
                }
                moveDragged(handled, translation: value.translation, space)
                dragFinger = value.location
                // The gap is read first: choosing it goes back and forth, and must not shake.
                updateProximity(space, time: now)
                if shake.add(value.location, time: now, suspended: composition.choosingGap) { return shakeOff(handled, space) }
            }
            .onEnded { value in
                let handled = lifted ?? id
                lifted = nil
                guard fusingPair == nil, composition.dragging == handled else { return }
                ignoreTapUntil = Date().addingTimeInterval(0.3)
                // Read the release location itself; do not rely on the last frame tick.
                moveDragged(handled, translation: value.translation, space)
                dragFinger = value.location
                updateProximity(space, time: Date().timeIntervalSinceReferenceDate)
                dragOrigin = nil
                dragFinger = nil
                if let pair = composition.endDrag() {
                    confirmCandidate(pair, space)
                } else {
                    bodies[handled]?.ramp = 0
                    settleIfReduced(space)
                }
            }
    }

    /// The word of the BubbleKey's phrase under a finger that went down at `start` and has rested
    /// there for `pickHold`: the one a pull takes out. Nil for any other bubble, a phrase of one
    /// word or one that wraps, a second finger, or a finger that moved at once.
    private func wordUnderHold(_ chip: WordChip, at start: CGPoint, _ space: Space, time: TimeInterval) -> Int? {
        guard chip.id == composition.focus, touches.count <= 1, let down = touchDown, time - down >= Self.pickHold,
              composition.focusPhrase.map({ $0.count > 1 }) == true, let layout = phrase(chip, space) else { return nil }
        let x = (start.x - rendered(chip, space, time: time).x) / focusScale(chip) + layout.size.width / 2
        let targets = layout.targets
        return targets.firstIndex { x < $0.maxX } ?? targets.count - 1
    }

    /// Takes word `index` out of the BubbleKey's phrase: the BubbleKey keeps the rest and the word
    /// buds out of the place where it stood. Returns what is left on the canvas, nil if it could
    /// not be taken out.
    @discardableResult
    private func takeOut(_ index: Int, of chip: WordChip, _ space: Space) -> Composition.Removed? {
        guard fusingPair == nil, let layout = phrase(chip, space), layout.words.indices.contains(index),
              let center = bodies[chip.id]?.position else { return nil }
        let word = layout.words[index]
        let stood = CGPoint(x: center.x + (word.midX - layout.size.width / 2) * focusScale(chip), y: center.y)
        dropPinch()
        fusionTask?.cancel()
        fusionTask = nil
        var removed: Composition.Removed?
        apply(space, origin: stood) { removed = composition.removeWord(at: index) }
        // The word under the finger is where it stood, not thrown out by the budding.
        if let id = removed?.word { bodies[id] = Physics.Body(position: stood) }
        return removed
    }

    /// The shaken bubble lets go where it is and buds related words; the rest of the drag is
    /// ignored until the finger lifts.
    private func shakeOff(_ id: UUID, _ space: Space) {
        suppressed.insert(id)
        dragOrigin = nil
        bodies[id]?.ramp = 0
        withAnimation(motion) { composition.cancel() }
        derive(id, space)
    }

    /// Mitosis without fusion: the related words bud out of the bubble, which stays.
    private func derive(_ id: UUID, _ space: Space) {
        guard fusingPair == nil else { return }
        let origin = bodies[id]?.position
        var budded = false
        apply(space, origin: origin) { budded = composition.derive(from: id) }
        if !budded { sfx.play(.error) }
    }

    private func moveDragged(_ id: UUID, translation: CGSize, _ space: Space) {
        guard let origin = dragOrigin, let size = space.sizes[id] else { return }
        let point = CGPoint(x: origin.x + translation.width, y: origin.y + translation.height)
        bodies[id] = Physics.Body(position: Physics.clamp(point, size: size, in: space.bounds))
    }

    private func updateProximity(_ space: Space, time: TimeInterval) {
        guard let id = composition.dragging, let size = space.sizes[id], let point = bodies[id]?.position else { return }
        let source = Physics.rect(point, size)
        let targets = composition.chips.compactMap { chip -> (id: UUID, gap: CGFloat, height: CGFloat)? in
            guard chip.id != id, composition.compatible(id, chip.id), let other = space.sizes[chip.id] else { return nil }
            let gap = Physics.signedDistance(source, Physics.rect(rendered(chip, space, time: time), other))
            return (chip.id, gap, min(size.height, other.height))
        }
        let closest = targets.min { $0.gap < $1.gap }
        let target = closest.flatMap { $0.gap <= composition.calibration.distance ? $0.id : nil }
        composition.updateProximity(target: target, penetration: closest.map { -$0.gap / $0.height } ?? 0, time: ProcessInfo.processInfo.systemUptime)
        updateInsertion(space, time: time)
    }

    /// The handled surface recoils from its partner while the membrane resists. In a pinch both
    /// surfaces hold a finger, so each takes half of the recoil.
    private func membraneOffset(_ chip: WordChip, _ space: Space, time: TimeInterval) -> CGSize {
        let pinched = composition.pinching?.contains(chip.id) == true
        guard !reduceMotion, pinched || composition.dragging == chip.id, composition.resistance > 0,
              let pair = composition.activePair,
              let other = composition.chips.first(where: { $0.id == (pair.source == chip.id ? pair.target : pair.source) }),
              let source = bodies[chip.id]?.position,
              let size = space.sizes[chip.id], let otherSize = space.sizes[other.id] else { return .zero }
        let to = rendered(other, space, time: time)
        let dx = source.x - to.x, dy = source.y - to.y
        let length = max(1, hypot(dx, dy))
        let gap = Physics.signedDistance(Physics.rect(source, size), Physics.rect(to, otherSize))
        let recoil = max(0, 36 - gap) * composition.resistance * (pinched ? 0.5 : 1)
        return CGSize(width: dx / length * recoil, height: dy / length * recoil)
    }

    // MARK: - Pinch

    /// Two fingers resting on two different chips hold them; each chip then follows its finger.
    /// The first finger to lift ends the pinch like releasing a drag.
    private func trackPinch(_ space: Space) {
        defer {
            if touches.isEmpty, !suppressed.isEmpty {
                ignoreTapUntil = Date().addingTimeInterval(0.3)
                suppressed = []
            }
        }
        if touches.count >= 2, tension != nil {
            tension = nil
            splitSound.cancel()
        }
        if let pinch {
            guard pinch.fingers.keys.allSatisfy({ touches[$0] != nil }) else { return finishPinch(space) }
            for (finger, id) in pinch.fingers {
                guard let start = pinch.touchStart[finger], let now = touches[finger],
                      let origin = pinch.chipStart[id], let size = space.sizes[id] else { continue }
                let point = CGPoint(x: origin.x + now.x - start.x, y: origin.y + now.y - start.y)
                bodies[id] = Physics.Body(position: Physics.clamp(point, size: size, in: space.bounds))
            }
            updatePinchProximity(space)
            return
        }
        guard touches.count == 2, suppressed.isEmpty, fusingPair == nil else { return }
        let now = Date().timeIntervalSinceReferenceDate
        let centers = Dictionary(uniqueKeysWithValues: composition.chips.map { ($0.id, rendered($0, space, time: now)) })
        var fingers: [ObjectIdentifier: UUID] = [:]
        for (finger, point) in touches {
            let local = CGPoint(x: point.x - canvasOrigin.x, y: point.y - canvasOrigin.y)
            guard let id = Physics.hit(local, centers: centers, sizes: space.sizes) else { return }
            fingers[finger] = id
        }
        let ids = composition.chips.map(\.id).filter { Set(fingers.values).contains($0) }
        guard ids.count == 2 else { return }
        // A drag in progress becomes the pinch without a jump and keeps its identity as the source.
        let source = composition.dragging.flatMap { ids.contains($0) ? $0 : nil } ?? ids[0]
        let target = ids[0] == source ? ids[1] : ids[0]
        dragOrigin = nil
        withAnimation(motion) { composition.beginPinch(source, target) }
        pinch = Pinch(fingers: fingers, touchStart: touches, chipStart: centers.filter { ids.contains($0.key) })
        updatePinchProximity(space)
    }

    private func finishPinch(_ space: Space) {
        let held = composition.pinching
        dropPinch()
        ignoreTapUntil = Date().addingTimeInterval(0.3)
        if let pair = composition.endPinch() {
            confirmCandidate(pair, space)
        } else {
            for id in [held?.source, held?.target].compactMap({ $0 }) { bodies[id]?.ramp = 0 }
            settleIfReduced(space)
        }
    }

    /// Forgets the fingers of a pinch; the ones still down are ignored until they lift.
    private func dropPinch() {
        guard let pinch else { return }
        suppressed.formUnion(pinch.fingers.values)
        self.pinch = nil
    }

    private func updatePinchProximity(_ space: Space) {
        guard let pair = composition.pinching,
              let a = bodies[pair.source]?.position, let b = bodies[pair.target]?.position,
              let sizeA = space.sizes[pair.source], let sizeB = space.sizes[pair.target] else { return }
        let gap = Physics.signedDistance(Physics.rect(a, sizeA), Physics.rect(b, sizeB))
        let penetration = gap <= composition.calibration.distance ? Double(-gap / min(sizeA.height, sizeB.height)) : nil
        composition.updatePinch(penetration: penetration, time: ProcessInfo.processInfo.systemUptime)
    }

    private func cancel(_ space: Space) {
        dropPinch()
        fusionTask?.cancel()
        fusionTask = nil
        fusingPair = nil
        lifted = nil
        withAnimation(motion) { composition.cancel(); dragOrigin = nil; dragFinger = nil }
        settleIfReduced(space)
    }

    /// Passive fusion: once an act's new words have budded, each twin of a word already shown
    /// glides into it and dissolves, so the canvas never shows one word twice.
    private func passiveFusion(_ space: Space) {
        passiveTask?.cancel()
        let ids = composition.chips.map(\.id)
        passiveTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            let pairs = composition.duplicates
            guard composition.chips.map(\.id) == ids, fusingPair == nil, let first = pairs.first else { return }
            if !reduceMotion {
                withAnimation(.easeIn(duration: 0.25)) {
                    fusingPair = MergePair(source: first.duplicate, target: first.keeper)
                    for pair in pairs {
                        if let p = bodies[pair.keeper]?.position { bodies[pair.duplicate] = Physics.Body(position: p) }
                    }
                }
                // Release the pair even if cancelled: a pair left fusing would freeze the physics.
                let glided = (try? await Task.sleep(for: .milliseconds(250))) != nil
                fusingPair = nil
                guard glided else { return }
            }
            guard composition.chips.map(\.id) == ids else { return }
            apply(space, sound: nil) { composition.absorbDuplicates() }
        }
    }

    /// `quiet` skips the split chime when the long-press burst already marks the moment.
    private func undo(_ id: UUID?, _ space: Space, quiet: Bool = false) {
        dropPinch()
        fusionTask?.cancel()
        fusionTask = nil
        fusingPair = nil
        dragOrigin = nil
        apply(space, sound: quiet ? nil : .split) {
            if let id { composition.split(id) } else { composition.undo() }
        }
    }
}

#Preview { ContentView() }
