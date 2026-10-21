import SwiftUI

/// The explorer's map, drawn like a Trizbort map on graph paper.
///
/// - Rooms appear once you've seen them (lit). Boxes are named; lines leave
///   each box from the side matching the exit's direction, so "north" really
///   is the top edge. up/down/in/out are labelled at the line's end.
/// - Arrowheads mark one-way passages. Short dotted stubs are exits you
///   haven't followed yet.
/// - The pulsing red ring is you.
/// - Tap a room to list its exits. Pinch to zoom, drag to pan, double-tap
///   to re-center. Swipe in from the right edge (or ▶) to return.
struct MapView: View {
    var onClose: () -> Void

    @Environment(GameEngine.self) private var engine
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var zoom: CGFloat = 1
    @State private var pinchBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
    @State private var selected: Int?

    private let map = CaveMap.shared
    /// Points per grid unit at zoom 1.
    private let unit: CGFloat = 96

    private let paper = Color(red: 0.975, green: 0.965, blue: 0.93)
    private let gridLine = Color(red: 0.55, green: 0.68, blue: 0.85)
    private let ink = Color(red: 0.13, green: 0.15, blue: 0.24)
    private let pencil = Color(red: 0.45, green: 0.47, blue: 0.52)
    private let wordInk = Color(red: 0.62, green: 0.16, blue: 0.14)
    private let here = Color(red: 0.86, green: 0.12, blue: 0.1)
    private let portalInk = Color(red: 0.12, green: 0.33, blue: 0.6)

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geo in
                canvas(size: geo.size)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Cave map")
                    .accessibilityValue(accessibilitySummary)
                    .overlay {
                        // Only the "you are here" marker animates; the map
                        // itself redraws only when something changes.
                        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                            let pulse = reduceMotion ? 0.5
                                : (sin(context.date.timeIntervalSinceReferenceDate * 4) + 1) / 2
                            hereMarker(size: geo.size, pulse: pulse)
                        }
                        .allowsHitTesting(false)
                    }
                .contentShape(Rectangle())
                .gesture(panGesture.simultaneously(with: zoomGesture))
                .onTapGesture(count: 2) { recenter(animated: true) }
                .onTapGesture { location in select(at: location, size: geo.size) }
                .overlay(alignment: .bottom) {
                    if let id = selected, let room = map.room(id) {
                        inspector(room)
                            .padding(10)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .background(paper)
            .clipped()
        }
        .background(paper.ignoresSafeArea())
        .onAppear { recenter(animated: false) }
        .onChange(of: engine.location) { selected = nil }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Cave Map")
                    .font(.system(size: 17, weight: .bold, design: .serif))
                Text("\(seenCount) of \(map.mappableCount) places seen")
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(pencil)
            }
            Spacer()
            Button {
                recenter(animated: true)
            } label: {
                Image(systemName: "location.fill")
            }
            .accessibilityLabel("Center on you")
            Button(action: onClose) {
                HStack(spacing: 3) {
                    Text("Game")
                    Image(systemName: "chevron.right")
                }
            }
            .padding(.leading, 14)
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(paper)
        .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.15)).frame(height: 1) }
    }

    // MARK: Geometry

    private var scale: CGFloat { unit * zoom }

    private var focusRoom: CaveMap.Room? {
        map.room(forLocation: engine.location) ?? lastSeenRoom
    }

    private var lastSeenRoom: CaveMap.Room? {
        map.rooms.first { room in room.locs.contains { engine.visited.contains($0) } }
    }

    /// Grid point → screen point.
    private func transform(size: CGSize) -> (CGPoint) -> CGPoint {
        let focus = focusRoom?.center ?? CGPoint(x: map.bounds.midX, y: map.bounds.midY)
        let s = scale
        let ox = size.width / 2 - focus.x * s + pan.width
        let oy = size.height / 2 - focus.y * s + pan.height
        return { p in CGPoint(x: ox + p.x * s, y: oy + p.y * s) }
    }

    private func isSeen(_ room: CaveMap.Room) -> Bool {
        room.locs.contains { engine.visited.contains($0) }
    }

    // MARK: Drawing

    private func canvas(size: CGSize) -> some View {
        let toScreen = transform(size: size)
        let s = scale
        let showStubs = settings.showUnexploredExits
        let seen = Set(map.rooms.filter(isSeen).map(\.id))
        let current = map.room(forLocation: engine.location)
        let detail = zoom >= 0.55

        return Canvas { ctx, canvasSize in
            // Graph paper
            let minor = s / 4
            if minor > 6 {
                let origin = toScreen(.zero)
                var path = Path()
                var x = origin.x.truncatingRemainder(dividingBy: minor)
                while x < canvasSize.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    x += minor
                }
                var y = origin.y.truncatingRemainder(dividingBy: minor)
                while y < canvasSize.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    y += minor
                }
                ctx.stroke(path, with: .color(gridLine.opacity(0.18)), lineWidth: 0.5)
            }

            // Region outlines, once any room inside has been seen
            for region in map.regions {
                guard map.rooms.contains(where: { $0.region == region.region && seen.contains($0.id) })
                else { continue }
                let p0 = toScreen(CGPoint(x: region.x0, y: region.y0))
                let p1 = toScreen(CGPoint(x: region.x1, y: region.y1))
                let rect = CGRect(x: p0.x, y: p0.y, width: p1.x - p0.x, height: p1.y - p0.y)
                ctx.stroke(Path(roundedRect: rect, cornerRadius: 8), with: .color(pencil.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                if detail {
                    ctx.draw(Text(region.title)
                                .font(.system(size: 11 * min(zoom, 1.3), weight: .medium, design: .serif))
                                .italic()
                                .foregroundColor(pencil),
                             at: CGPoint(x: rect.minX + 8, y: rect.minY + 6), anchor: .topLeading)
                }
            }

            // Passages
            let lineWidth = max(1, 1.6 * min(zoom, 1.4))
            for c in map.connections {
                guard let ra = map.room(c.a), let rb = map.room(c.b) else { continue }
                let seenA = seen.contains(ra.id), seenB = seen.contains(rb.id)
                if c.portal {
                    // Off-page connector: a stub at each known end, saying
                    // where it leads.
                    for (room, port, other, seenHere, seenThere) in [(ra, c.aPort, rb, seenA, seenB),
                                                                     (rb, c.bPort, ra, seenB, seenA)] where seenHere {
                        let p = map.portPoint(room, port)
                        let v = CaveMap.vector(port)
                        let len = hypot(v.dx, v.dy)
                        let q = CGPoint(x: p.x + v.dx / len * 0.26, y: p.y + v.dy / len * 0.26)
                        var path = Path()
                        path.move(to: toScreen(p))
                        path.addLine(to: toScreen(q))
                        ctx.stroke(path, with: .color(ink), lineWidth: lineWidth)
                        if detail {
                            let name = seenThere ? other.label : "?"
                            ctx.draw(Text("to " + name)
                                        .font(.system(size: 9.5 * min(max(zoom, 0.8), 1.5), weight: .semibold,
                                                      design: .serif))
                                        .foregroundColor(portalInk),
                                     at: toScreen(CGPoint(x: q.x + v.dx / len * 0.1, y: q.y + v.dy / len * 0.1)),
                                     anchor: v.dx > 0 ? .leading : (v.dx < 0 ? .trailing : .center))
                        }
                    }
                    continue
                }

                if c.isLoop {
                    guard seenA else { continue }
                    let p = toScreen(map.portPoint(ra, c.aPort))
                    let v = CaveMap.vector(c.aPort)
                    let r = 0.09 * s
                    let center = CGPoint(x: p.x + v.dx * r, y: p.y + v.dy * r)
                    ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                                      width: r * 2, height: r * 2)),
                               with: .color(ink), lineWidth: lineWidth)
                    continue
                }

                if seenA && seenB {
                    guard let pts = map.route(c)?.map(toScreen) else { continue }
                    var path = Path()
                    path.addLines(pts)
                    ctx.stroke(path, with: .color(ink),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    if c.oneWay { drawArrow(ctx, pts: pts, toB: c.aToB, size: 0.075 * s) }
                    if detail {
                        drawWord(ctx, c.aLabel, room: ra, port: c.aPort, toScreen: toScreen, s: s)
                        drawWord(ctx, c.bLabel, room: rb, port: c.bPort, toScreen: toScreen, s: s)
                    }
                } else if showStubs && ((seenA && c.aToB) || (seenB && c.bToA)) {
                    // An exit from a known room into the unknown.
                    let (room, port, label) = seenA ? (ra, c.aPort, c.aLabel) : (rb, c.bPort, c.bLabel)
                    let p = map.portPoint(room, port)
                    let v = CaveMap.vector(port)
                    let len = hypot(v.dx, v.dy)
                    let q = CGPoint(x: p.x + v.dx / len * 0.3, y: p.y + v.dy / len * 0.3)
                    var path = Path()
                    path.move(to: toScreen(p))
                    path.addLine(to: toScreen(q))
                    ctx.stroke(path, with: .color(ink.opacity(0.55)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [2, 3]))
                    if detail {
                        ctx.draw(Text("?").font(.system(size: 10 * min(zoom, 1.4), weight: .bold, design: .serif))
                                    .foregroundColor(ink.opacity(0.6)),
                                 at: toScreen(CGPoint(x: q.x + v.dx / len * 0.06, y: q.y + v.dy / len * 0.06)))
                        drawWord(ctx, label, room: room, port: port, toScreen: toScreen, s: s)
                    }
                }
            }

            // Rooms
            let w = map.boxW * s, h = map.boxH * s
            for room in map.rooms where seen.contains(room.id) || room.id == current?.id {
                let c = toScreen(room.center)
                let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
                guard rect.intersects(CGRect(origin: .zero, size: canvasSize).insetBy(dx: -20, dy: -20))
                else { continue }
                let shape = Path(roundedRect: rect, cornerRadius: 3)
                let isHere = room.id == current?.id
                let isSelected = room.id == selected
                ctx.fill(shape, with: .color(isSelected ? Color(red: 1, green: 0.96, blue: 0.75) : .white))
                ctx.stroke(shape, with: .color(ink), lineWidth: isHere ? 2.4 : 1.4)
                if detail {
                    let size = 9.5 * min(max(zoom, 0.85), 1.7)
                    // In the dark, an unseen room's name stays a mystery.
                    let label = seen.contains(room.id) ? room.label : "?"
                    let lines = wrapLabel(label, maxWidth: w - 8, ctx: ctx, size: size, bold: isHere)
                    let lineH = size * 1.18
                    let top = c.y - lineH * CGFloat(lines.count - 1) / 2
                    for (i, line) in lines.enumerated() {
                        ctx.draw(line, at: CGPoint(x: c.x, y: top + lineH * CGFloat(i)))
                    }
                }
            }

            let hereSeen = current.map({ seen.contains($0.id) }) ?? false
            if engine.isDark && !hereSeen {
                ctx.draw(Text("It is pitch dark. You can't see where you are.")
                            .font(.system(size: 13, weight: .semibold, design: .serif))
                            .foregroundColor(here),
                         at: CGPoint(x: canvasSize.width / 2, y: 22))
            }

            if seen.isEmpty {
                ctx.draw(Text("Nothing explored yet.")
                            .font(.system(size: 14, design: .serif)).italic()
                            .foregroundColor(pencil),
                         at: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2 + 70))
            }
        }
    }

    /// The pulsing ring and "YOU ARE HERE" tag, drawn on its own layer.
    private func hereMarker(size: CGSize, pulse: Double) -> some View {
        let toScreen = transform(size: size)
        let s = scale
        let w = map.boxW * s, h = map.boxH * s
        let me = map.room(forLocation: engine.location)
        return Canvas { ctx, _ in
            guard let me else { return }
            let c = toScreen(me.center)
            let r = max(w, h) * 0.62 + CGFloat(pulse) * 6
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.78, width: r * 2, height: r * 1.56)),
                       with: .color(here.opacity(0.85 - pulse * 0.35)), lineWidth: 2.5)
            let tag = ctx.resolve(Text("YOU ARE HERE")
                                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                                    .foregroundColor(.white))
            let tagSize = tag.measure(in: CGSize(width: 200, height: 40))
            let tagRect = CGRect(x: c.x - tagSize.width / 2 - 6, y: c.y - h / 2 - tagSize.height - 14,
                                 width: tagSize.width + 12, height: tagSize.height + 5)
            ctx.fill(Path(roundedRect: tagRect, cornerRadius: tagRect.height / 2), with: .color(here))
            ctx.draw(tag, at: CGPoint(x: tagRect.midX, y: tagRect.midY))
        }
    }

    /// Greedy word wrap into at most three centred lines.
    private func wrapLabel(_ label: String, maxWidth: CGFloat, ctx: GraphicsContext,
                           size: CGFloat, bold: Bool) -> [GraphicsContext.ResolvedText] {
        func resolve(_ s: String) -> GraphicsContext.ResolvedText {
            ctx.resolve(Text(s)
                .font(.system(size: size, weight: bold ? .bold : .regular, design: .serif))
                .foregroundColor(ink))
        }
        func width(_ s: String) -> CGFloat {
            resolve(s).measure(in: CGSize(width: 1000, height: 100)).width
        }
        var lines: [String] = []
        var current = ""
        for word in label.split(separator: " ").map(String.init) {
            let trial = current.isEmpty ? word : current + " " + word
            if width(trial) <= maxWidth || current.isEmpty {
                current = trial
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty { lines.append(current) }
        if lines.count > 3 {
            lines = Array(lines.prefix(3))
            lines[2] += "…"
        }
        return lines.map(resolve)
    }

    private func drawArrow(_ ctx: GraphicsContext, pts: [CGPoint], toB: Bool, size: CGFloat) {
        var a = pts[1], b = pts[2]
        if !toB { swap(&a, &b) }
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let ang = atan2(b.y - a.y, b.x - a.x)
        var tri = Path()
        tri.move(to: CGPoint(x: mid.x + cos(ang) * size, y: mid.y + sin(ang) * size))
        tri.addLine(to: CGPoint(x: mid.x + cos(ang + 2.5) * size, y: mid.y + sin(ang + 2.5) * size))
        tri.addLine(to: CGPoint(x: mid.x + cos(ang - 2.5) * size, y: mid.y + sin(ang - 2.5) * size))
        tri.closeSubpath()
        ctx.fill(tri, with: .color(ink))
    }

    private func drawWord(_ ctx: GraphicsContext, _ word: String, room: CaveMap.Room, port: String,
                          toScreen: (CGPoint) -> CGPoint, s: CGFloat) {
        guard !word.isEmpty else { return }
        let p = map.portPoint(room, port)
        let v = CaveMap.vector(port)
        // Beside the line, just outside the box.
        let side = CGPoint(x: v.dy == 0 ? 0 : 0.09, y: v.dx == 0 ? 0 : -0.07)
        let at = CGPoint(x: p.x + v.dx * 0.1 + side.x, y: p.y + v.dy * 0.1 + side.y)
        ctx.draw(Text(word)
                    .font(.system(size: 9 * min(max(zoom, 0.8), 1.5), weight: .semibold, design: .serif))
                    .italic()
                    .foregroundColor(wordInk),
                 at: toScreen(at))
    }

    // MARK: Inspector

    private func inspector(_ room: CaveMap.Room) -> some View {
        let groups = Dictionary(grouping: room.exits, by: \.to)
        let rows = groups.keys.sorted().compactMap { to -> (String, String, Bool)? in
            guard let exits = groups[to], let dest = map.room(to) else { return nil }
            let words = exits.flatMap(\.words).reduce(into: [String]()) { out, w in
                if !out.contains(w) { out.append(w) }
            }
            let name = isSeen(dest) ? dest.label : "?"
            return (words.prefix(4).joined(separator: ", "), name, exits.allSatisfy(\.conditional))
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(room.label).font(.system(size: 16, weight: .bold, design: .serif))
                Spacer()
                Button {
                    withAnimation(.snappy) { selected = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(pencil)
                }
                .accessibilityLabel("Close")
            }
            if rows.isEmpty {
                Text("No known way out.").font(.system(size: 13, design: .serif)).italic()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(rows.indices, id: \.self) { i in
                        let row = rows[i]
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(row.0)
                                .font(.system(size: 13, weight: .semibold, design: .serif))
                                .italic()
                                .foregroundStyle(wordInk)
                            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(pencil)
                            Text(row.1).font(.system(size: 13, design: .serif))
                            if row.2 {
                                Text("(sometimes)").font(.system(size: 11, design: .serif)).foregroundStyle(pencil)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
        }
        .foregroundStyle(ink)
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(ink.opacity(0.25)))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private func select(at point: CGPoint, size: CGSize) {
        let toScreen = transform(size: size)
        let w = map.boxW * scale, h = map.boxH * scale
        let hit = map.rooms.first { room in
            guard isSeen(room) else { return false }
            let c = toScreen(room.center)
            return abs(point.x - c.x) <= w / 2 + 4 && abs(point.y - c.y) <= h / 2 + 4
        }
        withAnimation(.snappy) { selected = hit?.id == selected ? nil : hit?.id }
    }

    // MARK: Gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                pan = CGSize(width: panBase.width + value.translation.width,
                             height: panBase.height + value.translation.height)
            }
            .onEnded { _ in panBase = pan }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(2.5, max(0.25, pinchBase * value.magnification))
            }
            .onEnded { _ in pinchBase = zoom }
    }

    private func recenter(animated: Bool) {
        let change = {
            pan = .zero
            panBase = .zero
            zoom = 1
            pinchBase = 1
        }
        if animated {
            withAnimation(.easeOut(duration: 0.25), change)
        } else {
            change()
        }
    }

    private var seenCount: Int {
        map.rooms.filter(isSeen).count
    }

    private var accessibilitySummary: String {
        let where_ = map.room(forLocation: engine.location)?.label ?? "an unknown place"
        return "You are at \(where_). \(seenCount) places seen."
    }
}
