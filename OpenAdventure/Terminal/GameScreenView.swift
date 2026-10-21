import SwiftUI

/// The text screen: transcript + live input line, rendered as a bitmap at
/// the machine's native resolution and passed through the CRT effect.
///
/// Drag vertically to scroll back through earlier text; any new output
/// snaps back to the bottom.
struct GameScreenView: View {
    @Environment(GameEngine.self) private var engine
    @Environment(AppSettings.self) private var settings

    @State private var cache = LayoutCache()
    @State private var scrollBack = 0
    @State private var dragStartScroll: Int?

    /// Characters are drawn a touch taller than wide, like on a real CRT.
    private static let pixelAspect: CGFloat = 1.15
    /// Dark border inside the picture, as on the real machine, so text stays
    /// clear of the tube's bent, rounded edges (fraction of width / height).
    private static let sideMargin: CGFloat = 0.055
    private static let topMargin: CGFloat = 0.025

    var body: some View {
        let crt = settings.crt
        GeometryReader { geo in
            // Fit as many whole rows as the monitor holds at this text size,
            // so text is never stretched or squashed.
            let columns = CGFloat(crt.columns)
            let textWidth = geo.size.width * (1 - 2 * Self.sideMargin)
            let usableHeight = geo.size.height * (1 - 2 * Self.topMargin)
            let rowHeight = textWidth / columns / CGFloat(PixelFont.cellWidth)
                * CGFloat(PixelFont.cellHeight) * Self.pixelAspect
            let rows = max(4, Int(usableHeight / max(rowHeight, 1)))
            let textHeight = CGFloat(rows) * rowHeight

            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let blinkOn = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                ZStack {
                    Color.black
                    if let image = makeImage(rows: rows, cursorVisible: blinkOn) {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: textWidth, height: textHeight)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .crt(crt, sourceRows: Double(rows * PixelFont.cellHeight) * Double(geo.size.height / textHeight))
            }
            .contentShape(Rectangle())
            .gesture(scrollGesture(rowHeight: rowHeight))
            .overlay(alignment: .bottomTrailing) {
                if scrollBack > 0 {
                    Button {
                        scrollBack = 0
                    } label: {
                        Image(systemName: "arrow.down.to.line")
                            .font(.caption.bold())
                            .padding(6)
                            .background(.black.opacity(0.6), in: Circle())
                            .foregroundStyle(crt.phosphor.color)
                    }
                    .padding(10)
                    .accessibilityLabel("Back to the latest text")
                }
            }
        }
        .onChange(of: engine.revision) { scrollBack = 0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Game screen")
        .accessibilityValue(accessibilityText)
    }

    private func makeImage(rows rowsOnScreen: Int, cursorVisible: Bool) -> CGImage? {
        let columns = settings.crt.columns
        let upper = settings.crt.uppercaseOnly
        let completed = cache.rows(engine: engine, columns: columns, uppercase: upper)

        var all = completed
        var cursor: (row: Int, column: Int)?
        let partial = engine.lines.last ?? ""
        if let prompt = engine.prompt {
            let live = TextLayout.liveRows(partial + prompt + engine.input,
                                           columns: columns, uppercase: upper)
            all.append(contentsOf: live.rows)
            cursor = (all.count - 1, live.cursorColumn)
        } else if engine.isOver || !partial.isEmpty {
            all.append(contentsOf: TextLayout.wrap(upper ? partial.uppercased() : partial,
                                                   width: columns))
        }

        let maxBack = max(0, all.count - rowsOnScreen)
        let back = min(scrollBack, maxBack)
        let end = all.count - back
        let start = max(0, end - rowsOnScreen)
        var window = Array(all[start..<end])
        while window.count < rowsOnScreen { window.append("") }

        var screenCursor: (row: Int, column: Int)?
        if let cursor, cursorVisible, back == 0 {
            screenCursor = (cursor.row - start, cursor.column)
        }
        return ScreenRenderer.image(for: .init(rows: window, columns: columns, cursor: screenCursor))
    }

    private func scrollGesture(rowHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                let start = dragStartScroll ?? scrollBack
                dragStartScroll = start
                // Pull down to reveal earlier text, like scrolling a page.
                let rows = Int((value.translation.height / max(rowHeight, 1)).rounded())
                scrollBack = max(0, start + rows)
            }
            .onEnded { _ in dragStartScroll = nil }
    }

    private var accessibilityText: String {
        let recent = engine.lines.suffix(12).joined(separator: "\n")
        return recent + (engine.prompt.map { "\n" + $0 + engine.input } ?? "")
    }
}

/// Wrapping the whole transcript on every keystroke would be wasteful, so
/// completed rows are cached until the transcript or the format changes.
@MainActor
final class LayoutCache {
    private var key: (revision: Int, columns: Int, upper: Bool)?
    private var cached: [String] = []

    func rows(engine: GameEngine, columns: Int, uppercase: Bool) -> [String] {
        if let key, key.revision == engine.revision, key.columns == columns, key.upper == uppercase {
            return cached
        }
        let completed = engine.lines.dropLast()
        cached = TextLayout.rows(forCompleted: completed, columns: columns, uppercase: uppercase)
        key = (engine.revision, columns, uppercase)
        return cached
    }
}
