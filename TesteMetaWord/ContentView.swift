import SwiftUI
import UIKit

struct ContentView: View {
    @State private var composition = Composition()
    @State private var bodies: [UUID: Physics.Body] = [:]
    @State private var lastTick: Date?
    @State private var dragOrigin: CGPoint?
    @State private var fusionTask: Task<Void, Never>?
    @State private var fusingPair: MergePair?
    @State private var showCalibration = false
    @State private var ignoreTapUntil = Date.distantPast
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var fontSize = 20.0
    @State private var splitSound = SplitSound()
    /// The master bubble under a long press that will split it, and when the press began.
    @State private var tension: (id: UUID, start: TimeInterval)?
    @GestureState private var pressing: UUID?

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

    var body: some View {
        GeometryReader { geometry in
            let width = max(160, geometry.size.width)
            let sizes = Dictionary(uniqueKeysWithValues: composition.chips.map { ($0.id, measure($0, width: width)) })
            let space = Space(sizes: sizes, canvas: CGSize(width: width, height: canvasHeight(sizes, width: width, viewport: max(300, geometry.size.height - 150))))
            VStack(spacing: 0) {
                toolbar(space)
                ScrollView {
                    TimelineView(.animation(paused: reduceMotion && composition.dragging == nil)) { context in
                        canvas(space, time: context.date.timeIntervalSinceReferenceDate)
                            .onChange(of: context.date) { _, date in tick(date, space) }
                    }
                }
                .scrollDisabled(composition.dragging != nil)
                status(space)
                    .frame(minHeight: 66)
                    .padding(.horizontal, 24)
            }
            .background {
                Button("Cancelar seleção") { cancel(space) }
                    .keyboardShortcut(.cancelAction)
                    .hidden()
                    .accessibilityHidden(true)
            }
            .onChange(of: geometry.size, initial: true) {
                cancel(space)
                if bodies.isEmpty, let first = composition.chips.first {
                    bodies = Physics.spawn(composition.chips.map(\.id), core: nil, at: space.center, seed: first.id)
                    settleIfReduced(space)
                }
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
        .task { await composition.refresh() }
        .onDisappear { fusionTask?.cancel() }
        .popover(isPresented: $showCalibration) { calibrationPanel }
    }

    private func canvas(_ space: Space, time: TimeInterval) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
                .onTapGesture { cancel(space) }
                .accessibilityHidden(true)
            atmosphere(space)
            GlassEffectContainer(spacing: 32) {
                ZStack(alignment: .topLeading) {
                    ForEach(composition.chips) { chip in
                        ChipView(
                            chip: chip, size: space.sizes[chip.id] ?? .zero,
                            selected: composition.selected == chip.id || composition.activePair?.contains(chip.id) == true,
                            armed: composition.dropCandidate?.contains(chip.id) == true || composition.candidate?.contains(chip.id) == true,
                            canUndo: composition.latestResult == chip.id,
                            namespace: glass,
                            activate: { activate(chip.id, space) },
                            undo: { undo(chip.id, space) }
                        )
                        .overlay {
                            Capsule().strokeBorder(.white.opacity(composition.dragging == chip.id ? composition.resistance * 0.85 : 0), lineWidth: 2)
                                .allowsHitTesting(false)
                        }
                        .offset(membraneOffset(chip, space, time: time))
                        .offset(tensionProgress(chip, time: time).map { SplitTension.offset(progress: $0, time: time) } ?? .zero)
                        .scaleEffect(tensionProgress(chip, time: time).map(SplitTension.scale) ?? 1)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: composition.resistance)
                        .position(rendered(chip, space, time: time))
                        .zIndex(composition.dragging == chip.id || fusingPair?.source == chip.id ? 1 : 0)
                        .transition(transition(for: chip))
                        .simultaneousGesture(drag(chip.id, space))
                        .simultaneousGesture(LongPressGesture(minimumDuration: SplitTension.duration)
                            .updating($pressing) { isPressing, state, _ in if isPressing { state = chip.id } }
                            .onEnded { _ in
                                guard canSplit(chip.id) else { return }
                                ignoreTapUntil = Date().addingTimeInterval(0.4)
                                splitSound.burst()
                                undo(chip.id, space)
                            })
                    }
                }
            }
        }
        .frame(width: space.canvas.width, height: space.canvas.height)
        .coordinateSpace(name: "canvas")
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

    /// Only the latest result divides, and never in the middle of another act.
    private func canSplit(_ id: UUID) -> Bool {
        fusingPair == nil && composition.dragging == nil && composition.latestResult == id
    }

    /// Long-press tension on the master bubble. No tremor with Reduce Motion; the sound remains.
    private func tensionProgress(_ chip: WordChip, time: TimeInterval) -> Double? {
        guard !reduceMotion, let tension, tension.id == chip.id else { return nil }
        return SplitTension.progress(since: tension.start, now: time)
    }

    /// Only occupied zones emit light. Outer fields have a clear interior, so an empty
    /// inner zone stays neutral. The compressed width is visual only; physics keeps full sizes.
    private func atmosphere(_ space: Space) -> some View {
        let size = composition.focus.flatMap { space.sizes[$0] } ?? CGSize(width: 56, height: 56)
        let occupied = Set(composition.zones.values).sorted()
        let focusEngaged = composition.focus.map { focus in
            composition.dragging == focus || composition.selected == focus
                || composition.activePair?.contains(focus) == true || fusingPair?.contains(focus) == true
        } ?? false
        return ZStack(alignment: .topLeading) {
            if let focus = composition.focus, let core = bodies[focus]?.position {
                ForEach(occupied, id: \.self) { zone in
                    let reach = 2 * (Physics.zoneGap(zone) + 68)
                    let inner = zone == 1 ? 0.12 : (size.height / 2 + Physics.zoneGap(zone - 1) + 36) / ((size.height + reach) / 2)
                    EllipticalGradient(gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: inner),
                        .init(color: .white.opacity(0.55), location: inner + (1 - inner) * 0.3),
                        .init(color: .white, location: inner + (1 - inner) * 0.5),
                        .init(color: .white.opacity(0.45), location: inner + (1 - inner) * 0.75),
                        .init(color: .clear, location: 1)
                    ]), endRadiusFraction: 0.5)
                    .frame(width: size.height + max(0, size.width - size.height) * 0.45 + reach,
                           height: size.height + reach)
                    .opacity(zone == 1 ? (focusEngaged ? 0.085 : 0.06) : zone == 2 ? 0.035 : 0.022)
                    .position(core)
                    .transition(.opacity)
                }
            }

            if let pair = composition.activePair,
               let a = bodies[pair.source]?.position, let b = bodies[pair.target]?.position {
                let armed = composition.dropCandidate != nil || composition.candidate != nil
                EllipticalGradient(colors: [.white, .white.opacity(0.45), .clear], endRadiusFraction: 0.5)
                    .frame(width: min(240, max(size.height * 2, abs(a.x - b.x) + 100)),
                           height: min(180, max(100, abs(a.y - b.y) + 80)))
                    .opacity((armed ? 0.13 : 0.055) * (1 - composition.resistance * 0.55))
                    .position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: composition.focus)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: occupied)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: size)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: focusEngaged)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: composition.activePair)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: composition.dropCandidate)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: composition.resistance)
        .transaction { if reduceMotion { $0.animation = nil } }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private var statusText: String {
        if fusingPair != nil { return "Combinando…" }
        if composition.dropCandidate != nil { return "Solte para combinar." }
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

    /// Grows the canvas when large text needs more room than the viewport.
    private func canvasHeight(_ sizes: [UUID: CGSize], width: CGFloat, viewport: CGFloat) -> CGFloat {
        let area = sizes.values.reduce(0) { $0 + ($1.width + Physics.restGap) * ($1.height + Physics.restGap) }
        return max(viewport, area / max(1, width - 32) * 1.5 + 32)
    }

    // MARK: - Physics and idle float

    /// Body position plus the idle orbit. Words being handled stop floating so they hold still.
    private func rendered(_ chip: WordChip, _ space: Space, time: TimeInterval) -> CGPoint {
        let position = bodies[chip.id]?.position ?? space.center
        let floats = !reduceMotion && composition.dragging != chip.id && composition.selected != chip.id
            && composition.activePair?.contains(chip.id) != true && fusingPair?.contains(chip.id) != true
            && tension?.id != chip.id
        let orbit = Physics.orbit(phase: chip.phase, time: time, amplitude: floats ? Physics.orbitAmplitude : 0)
        return CGPoint(x: position.x + orbit.dx, y: position.y + orbit.dy)
    }

    /// Fusion results cross-fade into place; every other new word buds out from a smaller scale.
    private func transition(for chip: WordChip) -> AnyTransition {
        if reduceMotion || chip.fusionCount > 0 { return .opacity }
        return .asymmetric(insertion: .scale(scale: 0.4).combined(with: .opacity), removal: .opacity)
    }

    /// The composition holds still during the act (drag, selection, prepared pair, fusion);
    /// repulsion and the zones reorganize it only afterwards.
    private var isActing: Bool {
        composition.dragging != nil || composition.selected != nil || composition.candidate != nil || fusingPair != nil
    }

    private func tick(_ date: Date, _ space: Space) {
        defer { lastTick = date }
        if composition.dragging != nil { updateProximity(space, time: date.timeIntervalSinceReferenceDate) }
        guard !reduceMotion, !isActing, let lastTick else { return }
        simulate(space, dt: min(1.0 / 30, date.timeIntervalSince(lastTick)))
    }

    private func simulate(_ space: Space, dt: CGFloat) {
        Physics.step(&bodies, sizes: space.sizes, focus: composition.focus, zones: composition.zones, center: space.center, bounds: space.bounds, dt: dt)
    }

    /// Reduce Motion: jump straight to equilibrium instead of animating the physics.
    private func settleIfReduced(_ space: Space) {
        guard reduceMotion, !isActing else { return }
        for _ in 0..<240 { simulate(space, dt: 1.0 / 60) }
    }

    /// Runs a composition change and gives each new word a body. New words are born where the
    /// words they replace were: the one inheriting a removed glass identity stays at the core and
    /// the others bud out (fusion → suggestions, undo → the second origin).
    private func apply(_ space: Space, _ change: () -> Void) {
        let before = composition.chips
        withAnimation(birth) { change() }
        let after = composition.chips
        let removed = before.filter { old in !after.contains { $0.id == old.id } }
        let added = after.filter { new in !before.contains { $0.id == new.id } }
        let core = added.first { new in removed.contains { $0.glassID == new.glassID } }
        let anchor = core.flatMap { core in removed.first { $0.glassID == core.glassID } }
        let removedPositions = removed.compactMap { bodies[$0.id]?.position }
        let centroid = removedPositions.isEmpty ? space.center : CGPoint(
            x: removedPositions.map(\.x).reduce(0, +) / CGFloat(removedPositions.count),
            y: removedPositions.map(\.y).reduce(0, +) / CGFloat(removedPositions.count))
        let origin = anchor.flatMap { bodies[$0.id]?.position } ?? centroid
        for chip in removed { bodies[chip.id] = nil }
        if let seed = (core ?? added.first)?.id {
            bodies.merge(Physics.spawn(added.map(\.id), core: core?.id, at: origin, seed: seed)) { $1 }
        }
        settleIfReduced(space)
        Task { await composition.refresh() }
    }

    // MARK: - Gestures

    private func activate(_ id: UUID, _ space: Space) {
        guard Date() >= ignoreTapUntil, fusingPair == nil else { return }
        if let pair = composition.candidate, pair.contains(id) {
            confirmCandidate(pair, space)
            return
        }
        withAnimation(motion) { composition.tap(id) }
        settleIfReduced(space)
    }

    /// Reverse mitosis: both origins converge to their midpoint, then the result is born there.
    private func confirmCandidate(_ pair: MergePair, _ space: Space) {
        guard !reduceMotion, let a = bodies[pair.source]?.position, let b = bodies[pair.target]?.position else {
            apply(space) { composition.tap(pair.source) }
            return
        }
        let center = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        withAnimation(.easeIn(duration: 0.2)) {
            fusingPair = pair
            bodies[pair.source] = Physics.Body(position: center)
            bodies[pair.target] = Physics.Body(position: center)
        }
        fusionTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard composition.candidate == pair else { cancel(space); return }
            apply(space) { composition.tap(pair.source) }
            fusingPair = nil
            fusionTask = nil
        }
    }

    private func drag(_ id: UUID, _ space: Space) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named("canvas"))
            .onChanged { value in
                guard fusingPair == nil, let chip = composition.chips.first(where: { $0.id == id }) else { return }
                let now = Date().timeIntervalSinceReferenceDate
                if composition.dragging != id {
                    dragOrigin = rendered(chip, space, time: now)
                    composition.beginDrag(id)
                }
                moveDragged(id, translation: value.translation, space)
                updateProximity(space, time: now)
            }
            .onEnded { value in
                guard fusingPair == nil, composition.dragging == id else { return }
                ignoreTapUntil = Date().addingTimeInterval(0.3)
                // Read the release location itself; do not rely on the last frame tick.
                moveDragged(id, translation: value.translation, space)
                updateProximity(space, time: Date().timeIntervalSinceReferenceDate)
                dragOrigin = nil
                if let pair = composition.endDrag() {
                    confirmCandidate(pair, space)
                } else {
                    settleIfReduced(space)
                }
            }
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
    }

    private func membraneOffset(_ chip: WordChip, _ space: Space, time: TimeInterval) -> CGSize {
        guard !reduceMotion, composition.dragging == chip.id, composition.resistance > 0,
              let pair = composition.activePair,
              let target = composition.chips.first(where: { $0.id == pair.target }),
              let source = bodies[chip.id]?.position,
              let size = space.sizes[chip.id], let targetSize = space.sizes[target.id] else { return .zero }
        let to = rendered(target, space, time: time)
        let dx = source.x - to.x, dy = source.y - to.y
        let length = max(1, hypot(dx, dy))
        let recoil = max(0, 36 - Physics.signedDistance(Physics.rect(source, size), Physics.rect(to, targetSize))) * composition.resistance
        return CGSize(width: dx / length * recoil, height: dy / length * recoil)
    }

    private func cancel(_ space: Space) {
        fusionTask?.cancel()
        fusionTask = nil
        fusingPair = nil
        withAnimation(motion) { composition.cancel(); dragOrigin = nil }
        settleIfReduced(space)
    }

    private func undo(_ id: UUID?, _ space: Space) {
        fusionTask?.cancel()
        fusionTask = nil
        fusingPair = nil
        dragOrigin = nil
        apply(space) { composition.undo(from: id) }
    }
}

#Preview { ContentView() }
