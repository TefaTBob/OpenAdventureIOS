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

/// One sculpted key cap, shaped like the Apple IIe's: a tapered body whose
/// sides and tall front skirt you can see, and a smaller top dished into a
/// gentle concave curve that catches the light along its front lip.
/// Fires on release (so a swipe that starts on a key doesn't type), shows
/// the press immediately.
struct KeyCap: View {
    let spec: KeySpec
    let unit: CGFloat
    let gap: CGFloat
    let height: CGFloat
    let onPress: (KeyAction) -> Void

    @State private var pressed = false

    var body: some View {
        let down = pressed
        let w = max(0, unit * spec.width - gap)
        let travel = max(2, height * 0.07)
        // The top is narrower than the base, and sits towards the back, so
        // more of the front skirt shows than the sides — the view from a
        // typist's seat.
        let side = min(w * 0.11, 5.5)
        let topH = height * 0.70
        let topY = (down ? travel : 0) + height * 0.04
        ZStack(alignment: .top) {
            // Body: tapered sides and front skirt.
            KeyBody(inset: side)
                .fill(LinearGradient(colors: [Retro.keyFace, Retro.keySkirt],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    // Light from the upper left: left wall lit, right in shade.
                    KeyBody(inset: side)
                        .fill(LinearGradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.28)],
                                             startPoint: .leading, endPoint: .trailing))
                )
                .overlay(
                    KeyBody(inset: side)
                        .stroke(.black.opacity(0.55), lineWidth: 0.75)
                )
                .padding(.top, down ? travel : 0)
                .shadow(color: .black.opacity(down ? 0.2 : 0.4), radius: down ? 0.5 : 1.5, y: down ? 0.5 : 2)

            // Top: dished. Darker under the back rim, lighter where the
            // curve turns up towards you, with a bright front lip.
            let top = RoundedRectangle(cornerRadius: min(7, w * 0.16), style: .continuous)
            top
                .fill(LinearGradient(stops: [
                    .init(color: Retro.keyFace.opacity(0.95), location: 0),
                    .init(color: Retro.keyFace, location: 0.18),
                    .init(color: Retro.keyTop, location: 0.72),
                    .init(color: Retro.keyTop.opacity(0.9), location: 1),
                ], startPoint: .top, endPoint: .bottom))
                .overlay(
                    // The dish: a soft sheen across the middle of the scoop.
                    top.fill(EllipticalGradient(colors: [.white.opacity(0.09), .clear],
                                                center: UnitPoint(x: 0.45, y: 0.62),
                                                startRadiusFraction: 0, endRadiusFraction: 0.6))
                )
                .overlay(
                    // Rim: shadowed at the back edge, catching light at the front lip.
                    top.strokeBorder(LinearGradient(colors: [.black.opacity(0.45), .clear, .white.opacity(0.22)],
                                                    startPoint: .top, endPoint: .bottom),
                                     lineWidth: 1.2)
                )
                .overlay { legendView }
                .frame(width: max(0, w - side * 2.4), height: topH)
                .offset(y: topY)
        }
        .frame(width: w, height: height, alignment: .top)
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
        .animation(.easeOut(duration: 0.06), value: pressed)
        .accessibilityElement()
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onPress(spec.action) }
    }

    @ViewBuilder private var legendView: some View {
        if let symbol = spec.symbol {
            Image(systemName: symbol)
                .font(.system(size: min(18, height * 0.36), weight: .semibold))
                .foregroundStyle(Retro.legend)
        } else {
            Text(spec.legend)
                .font(.system(size: spec.small ? min(12, height * 0.25) : min(21, height * 0.44),
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

/// The key's body seen from above and in front: a rounded trapezoid whose
/// top edge is pulled in by `inset` on each side.
struct KeyBody: Shape {
    var inset: CGFloat

    func path(in r: CGRect) -> Path {
        let rad = min(6, r.width * 0.18)
        let tl = CGPoint(x: r.minX + inset, y: r.minY)
        let tr = CGPoint(x: r.maxX - inset, y: r.minY)
        let br = CGPoint(x: r.maxX, y: r.maxY)
        let bl = CGPoint(x: r.minX, y: r.maxY)
        var p = Path()
        p.move(to: CGPoint(x: (tl.x + tr.x) / 2, y: r.minY))
        p.addArc(tangent1End: tr, tangent2End: br, radius: rad)
        p.addArc(tangent1End: br, tangent2End: bl, radius: rad)
        p.addArc(tangent1End: bl, tangent2End: tl, radius: rad)
        p.addArc(tangent1End: tl, tangent2End: tr, radius: rad)
        p.closeSubpath()
        return p
    }
}
