import SwiftUI

/// Three pages side by side: map ◀ game ▶ notes.
///
/// On the game page, swipe the monitor right for the map or left for the
/// notepad. The map pans with drags, so it closes with a swipe in from its
/// right edge (or the header button); the notepad closes with a swipe in
/// from its left edge.
struct RootView: View {
    enum Page: Int { case map = 0, game, notes }

    @Environment(GameEngine.self) private var engine
    @State private var page: Page = .game
    @State private var dragX: CGFloat = 0
    @State private var transitioning = false
    @State private var showSettings = false
    @FocusState private var hardwareKeyboardFocus: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            HStack(spacing: 0) {
                pageSlot(.map, width: width) {
                    MapView(onClose: { go(.game, width: width) })
                        .overlay(alignment: .trailing) {
                            edgeSwipe(width: width, closingFromTrailing: true)
                        }
                }
                pageSlot(.game, width: width) { gamePage(width: width) }
                pageSlot(.notes, width: width) {
                    NotepadView(onClose: { go(.game, width: width) })
                        .overlay(alignment: .leading) {
                            edgeSwipe(width: width, closingFromTrailing: false)
                        }
                }
            }
            .offset(x: -CGFloat(page.rawValue) * width + dragX)
            .frame(width: width, alignment: .leading)
        }
        .background(Retro.caseBottom.ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }

    /// Off-screen pages are only built while they could be seen, so the map's
    /// shader isn't running behind the game.
    @ViewBuilder
    private func pageSlot<Content: View>(_ slot: Page, width: CGFloat,
                                         @ViewBuilder content: () -> Content) -> some View {
        let showing = slot == page
            || ((dragX != 0 || transitioning) && abs(slot.rawValue - page.rawValue) == 1)
        Group {
            if showing {
                content()
            } else {
                Retro.caseBottom
            }
        }
        .frame(width: width)
    }

    // MARK: Game page

    private func gamePage(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            // The monitor takes all the room the keyboard and score leave.
            MonitorView {
                // A little black margin so the first column clears the glass edge.
                GameScreenView()
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(Color.black)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .frame(maxHeight: .infinity)
            .simultaneousGesture(pageSwipe(width: width))

            statusStrip
                .padding(.top, 6)
                .padding(.bottom, 4)

            KeyboardView(
                onSettings: { showSettings = true },
                onMap: { go(.map, width: width) },
                onNotes: { go(.notes, width: width) }
            )
            .frame(height: KeyboardLayout.height(forWidth: width))
        }
        .focusable()
        .focused($hardwareKeyboardFocus)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in handleHardwareKey(press) }
        .onAppear { hardwareKeyboardFocus = true }
    }

    private var statusStrip: some View {
        HStack(spacing: 18) {
            Text("SCORE \(engine.score)/\(engine.maxScore)")
            Text("TURNS \(engine.turns)")
            Spacer()
            Image(systemName: engine.isDark ? "moon.fill" : "lightbulb.fill")
                .accessibilityLabel(engine.isDark ? "Dark" : "Lit")
        }
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .foregroundStyle(Retro.caseShadow)
        .padding(.horizontal, 16)
    }

    // MARK: Paging

    private func go(_ target: Page, width: CGFloat) {
        guard target != page else {
            withAnimation(.snappy) { dragX = 0 }
            return
        }
        transitioning = true
        withAnimation(.snappy(duration: 0.3)) {
            page = target
            dragX = 0
        } completion: {
            transitioning = false
            if target == .game { hardwareKeyboardFocus = true }
        }
    }

    private func pageSwipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                let dx = value.translation.width
                guard abs(dx) > abs(value.translation.height) * 1.4 else { return }
                dragX = dx
            }
            .onEnded { value in
                let dx = value.predictedEndTranslation.width
                if dragX == 0 { return }
                if dx > width * 0.3 {
                    go(page == .notes ? .game : .map, width: width)
                } else if dx < -width * 0.3 {
                    go(page == .map ? .game : .notes, width: width)
                } else {
                    go(page, width: width)
                }
            }
    }

    /// A thin strip at a page edge that drags the game page back in.
    private func edgeSwipe(width: CGFloat, closingFromTrailing: Bool) -> some View {
        Color.clear
            .frame(width: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        let dx = value.translation.width
                        dragX = closingFromTrailing ? min(0, dx) : max(0, dx)
                    }
                    .onEnded { value in
                        let dx = value.predictedEndTranslation.width
                        let far = closingFromTrailing ? dx < -width * 0.25 : dx > width * 0.25
                        go(far ? .game : page, width: width)
                    }
            )
    }

    // MARK: Hardware keyboard (iPad, Bluetooth)

    private func handleHardwareKey(_ press: KeyPress) -> KeyPress.Result {
        guard page == .game, !showSettings else { return .ignored }
        switch press.key {
        case .return: engine.submit()
        case .delete: engine.backspace()
        case .escape: engine.clearInput()
        case .tab: engine.recallPrevious()
        case .upArrow: engine.send("north")
        case .downArrow: engine.send("south")
        case .leftArrow: engine.send("west")
        case .rightArrow: engine.send("east")
        default:
            let printable = press.characters.filter { $0.isASCII && !$0.isNewline && ($0.isLetter || $0.isNumber || $0.isPunctuation || $0.isSymbol || $0 == " ") }
            guard !printable.isEmpty, !press.modifiers.contains(.command) else { return .ignored }
            engine.type(printable)
        }
        return .handled
    }
}
