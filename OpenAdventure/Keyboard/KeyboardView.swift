import AudioToolbox
import SwiftUI
import UIKit

/// What a key does.
enum KeyAction: Equatable {
    case letter(Character)
    case space, delete, returnKey
    case previous        // bring back the last command
    case map, notes, settings
}

struct KeySpec: Identifiable {
    let id: String
    let action: KeyAction
    /// Width in key units (a letter key is 1).
    let width: CGFloat
    let legend: String
    var symbol: String? = nil   // SF Symbol instead of text
    var small = false           // word legends ("RETURN") use small type
}

/// An iPhone-style layout with Apple IIe key caps: just what the game needs.
///
///     Q W E R T Y U I O P
///      A S D F G H J K L
///     ↺  Z X C V B N M  ⌫
///     ⚙ 🗺  [  space  ] 📝 RETURN
///
/// ↺ brings back your previous command (tap again to go further back).
/// The game ignores case, so there is no shift: letters type in capitals,
/// as on the original machine.
enum KeyboardLayout {
    static let unitsPerRow: CGFloat = 10
    static let rowCount = 4

    static let rows: [[KeySpec]] = makeRows()

    private static func makeRows() -> [[KeySpec]] {
        let top: [KeySpec] = letters("QWERTYUIOP")
        let home: [KeySpec] = letters("ASDFGHJKL")
        var third: [KeySpec] = [KeySpec(id: "previous", action: .previous, width: 1.5,
                                        legend: "", symbol: "arrow.counterclockwise")]
        third.append(contentsOf: letters("ZXCVBNM"))
        third.append(KeySpec(id: "delete", action: .delete, width: 1.5, legend: "", symbol: "delete.left"))
        let bottom: [KeySpec] = [
            KeySpec(id: "settings", action: .settings, width: 1.25, legend: "", symbol: "gearshape.fill"),
            KeySpec(id: "map", action: .map, width: 1.25, legend: "", symbol: "map"),
            KeySpec(id: "space", action: .space, width: 4.25, legend: ""),
            KeySpec(id: "notes", action: .notes, width: 1.25, legend: "", symbol: "note.text"),
            KeySpec(id: "return", action: .returnKey, width: 2, legend: "RETURN", small: true),
        ]
        return [top, home, third, bottom]
    }

    private static func letters(_ s: String) -> [KeySpec] {
        s.map { c in KeySpec(id: String(c), action: .letter(c), width: 1, legend: String(c)) }
    }

    /// Height of the whole keyboard for a given width (RootView reserves it).
    static func height(forWidth width: CGFloat) -> CGFloat {
        let m = metrics(width: width)
        return m.inset * 2 + CGFloat(rowCount) * m.keyHeight + CGFloat(rowCount - 1) * m.rowGap
    }

    static func metrics(width: CGFloat) -> (unit: CGFloat, gap: CGFloat, keyHeight: CGFloat,
                                             rowGap: CGFloat, inset: CGFloat) {
        let inset: CGFloat = 4
        let unit = (width - inset * 2) / unitsPerRow
        let gap = min(6, unit * 0.15)
        // iPhone keys are about 42–46 pt tall at 32–40 pt wide.
        let keyHeight = min(52, max(40, (unit - gap) * 1.32))
        return (unit, gap, keyHeight, 10, inset)
    }
}

/// The keyboard, set into a beige case like the front of the machine.
struct KeyboardView: View {
    var onSettings: () -> Void
    var onMap: () -> Void
    var onNotes: () -> Void

    @Environment(GameEngine.self) private var engine
    @Environment(AppSettings.self) private var settings

    private let feedback = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        GeometryReader { geo in
            let m = KeyboardLayout.metrics(width: geo.size.width)
            VStack(spacing: m.rowGap) {
                ForEach(KeyboardLayout.rows.indices, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(KeyboardLayout.rows[r]) { spec in
                            KeyCap(spec: spec, unit: m.unit, gap: m.gap, height: m.keyHeight,
                                   onPress: press)
                        }
                    }
                    .frame(maxWidth: .infinity)   // the shorter home row centres
                }
            }
            .padding(m.inset)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .background(
            LinearGradient(colors: [Retro.caseTop, Retro.caseBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
        .onAppear { feedback.prepare() }
    }

    private func press(_ action: KeyAction) {
        if settings.haptics { feedback.impactOccurred() }
        if settings.keyClicks { AudioServicesPlaySystemSound(1104) }

        switch action {
        case .letter(let c): engine.type(String(c).uppercased())
        case .space: engine.type(" ")
        case .delete: engine.backspace()
        case .returnKey: engine.submit()
        case .previous: engine.recallPrevious()
        case .map: onMap()
        case .notes: onNotes()
        case .settings: onSettings()
        }
    }
}

/// One sculpted key cap. Fires on release (so a swipe that starts on a key
/// doesn't type), shows the press immediately.
struct KeyCap: View {
    let spec: KeySpec
    let unit: CGFloat
    let gap: CGFloat
    let height: CGFloat
    let onPress: (KeyAction) -> Void

    @State private var pressed = false

    var body: some View {
        let down = pressed
        let travel = max(1.5, height * 0.06)
        ZStack(alignment: .top) {
            // Skirt (the key's sides, seen from above)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Retro.keySkirt)
            // Top surface, slightly dished
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(LinearGradient(colors: [Retro.keyTop, Retro.keyFace],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .padding(.horizontal, unit * 0.07)
                .padding(.top, down ? travel : 1)
                .padding(.bottom, down ? 1 : travel + 1)
                .overlay(alignment: .center) { legendView.offset(y: down ? travel / 2 : -travel / 2) }
        }
        .frame(width: max(0, unit * spec.width - gap), height: height)
        .padding(.horizontal, gap / 2)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true } }
                .onEnded { value in
                    pressed = false
                    if abs(value.translation.width) < unit * spec.width * 0.9,
                       abs(value.translation.height) < height * 0.9 {
                        onPress(spec.action)
                    }
                }
        )
        .accessibilityElement()
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onPress(spec.action) }
    }

    @ViewBuilder private var legendView: some View {
        if let symbol = spec.symbol {
            Image(systemName: symbol)
                .font(.system(size: min(20, height * 0.4), weight: .semibold))
                .foregroundStyle(Retro.legend)
        } else {
            Text(spec.legend)
                .font(.system(size: spec.small ? min(13, height * 0.28) : min(24, height * 0.5),
                              weight: spec.small ? .semibold : .medium,
                              design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Retro.legend)
                .padding(.horizontal, 2)
        }
    }

    private var accessibilityName: String {
        switch spec.action {
        case .letter(let c): String(c)
        case .space: "Space"
        case .delete: "Delete"
        case .returnKey: "Return"
        case .previous: "Previous command"
        case .map: "Open map"
        case .notes: "Open notes"
        case .settings: "Settings"
        }
    }
}
