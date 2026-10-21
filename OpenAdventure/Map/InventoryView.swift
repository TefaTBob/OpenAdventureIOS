import SwiftUI

/// What you're carrying, as a page of the explorer's notebook: each thing
/// sketched in ink beside the game's own name for it. Opened from the
/// backpack button on the map.
struct InventoryView: View {
    @Environment(GameEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    private let art = MapArt.shared
    private let paper = Color(red: 0.965, green: 0.945, blue: 0.898)
    private let ink = MapArt.Ink.ink.color
    private let pencil = MapArt.Ink.soft.color
    private let hand = "Noteworthy-Light"
    private let handBold = "Noteworthy-Bold"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "backpack")
                Text("Inventory").font(.custom(handBold, size: 20))
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 8)

            if engine.carried.isEmpty && !engine.bearFollowing {
                Text("You're not carrying anything.")
                    .font(.custom(hand, size: 16))
                    .foregroundStyle(pencil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(engine.carried) { item in
                            row(sketch: art.items[item.id], name: item.name)
                        }
                        if engine.bearFollowing {
                            row(sketch: nil, name: "A tame bear, following you", symbol: "pawprint")
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(paper.ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }

    private func row(sketch: MapArt.ItemArt?, name: String, symbol: String = "questionmark") -> some View {
        HStack(spacing: 14) {
            Group {
                if let sketch {
                    ItemSketch(item: sketch)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 22))
                        .foregroundStyle(MapArt.Ink.brown.color)
                }
            }
            .frame(width: 52, height: 46)
            Text(name)
                .font(.custom(hand, size: 17))
                .foregroundStyle(ink)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            // A ruled line, as on a notebook page.
            Rectangle().fill(MapArt.Ink.blue.color.opacity(0.18)).frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}

/// One inventory sketch, scaled to fit its box.
struct ItemSketch: View {
    let item: MapArt.ItemArt

    var body: some View {
        Canvas { ctx, size in
            let b = item.bounds.isNull ? CGRect(x: -12, y: -12, width: 24, height: 24) : item.bounds
            let k = min(size.width / max(b.width, 1), size.height / max(b.height, 1), 2.0)
            var c = ctx
            c.translateBy(x: size.width / 2, y: size.height / 2)
            c.scaleBy(x: k, y: k)
            c.translateBy(x: -b.midX, y: -b.midY)
            for g in item.groups {
                c.stroke(g.path, with: .color(g.ink.color),
                         style: StrokeStyle(lineWidth: g.width * 1.1 / k + 0.25, lineCap: .round,
                                            lineJoin: .round, dash: g.dash))
            }
            for l in item.labels {
                var t = c
                t.translateBy(x: l.at.x, y: l.at.y)
                t.rotate(by: l.rotation)
                t.draw(Text(l.text)
                        .font(.custom(l.bold ? "Noteworthy-Bold" : "Noteworthy-Light", size: l.size))
                        .foregroundColor(l.ink.color),
                       at: .zero)
            }
        }
    }
}
