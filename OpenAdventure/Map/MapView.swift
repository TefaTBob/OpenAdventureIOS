import SwiftUI

/// The explorer's map, pencilled Trizbort-style onto graph paper.
///
/// - Rooms appear once you've seen them (lit). Boxes are named; lines leave
///   each box from the side matching the exit's direction, so "north" really
///   is the top edge. Beside each end of a line is the command that takes
///   you along it, the game's way: N, NE, U, IN… ("N/D" when both work).
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
    /// Graphite: a soft, slightly warm dark grey.
    private let ink = Color(red: 0.22, green: 0.22, blue: 0.25)
    private let pencil = Color(red: 0.45, green: 0.45, blue: 0.48)
    private let wordInk = Color(red: 0.32, green: 0.32, blue: 0.36)
    private let here = Color(red: 0.82, green: 0.14, blue: 0.12)   // red pencil
    private let portalInk = Color(red: 0.32, green: 0.32, blue: 0.36)
    private let hand = "Noteworthy-Light"
    private let handBold = "Noteworthy-Bold"

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
                    .font(.custom(handBold, size: 20))
                Text("\(seenCount) of \(map.mappableCount) places seen")
                    .font(.custom(hand, size: 12))
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
                let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                               CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
                               CGPoint(x: rect.minX, y: rect.minY)]
                Pencil.stroke(ctx, corners, seed: region.title.count &* 31, width: 1,
                              color: pencil.opacity(0.7), dash: [6, 5])
                if detail {
                    ctx.draw(Text(region.title)
                                .font(.custom(hand, size: 12 * min(zoom, 1.3)))
                                .foregroundColor(pencil),
                             at: CGPoint(x: rect.minX + 8, y: rect.minY + 4), anchor: .topLeading)
                }
            }

            // Passages
            let lineWidth = max(1, 1.3 * min(zoom, 1.4))
            // Command tags: (text, port point, direction out of the box, which side of the line).
            var tags: [(text: String, at: CGPoint, out: CGVector, flip: Bool)] = []
            for c in map.connections {
                guard let ra = map.room(c.a), let rb = map.room(c.b) else { continue }
                let seenA = seen.contains(ra.id), seenB = seen.contains(rb.id)
                let seed = c.a &* 1009 &+ c.b
                if c.portal {
                    // Off-page connector: a stub at each known end, saying
                    // where it leads.
                    for (room, port, other, seenHere, seenThere) in [(ra, c.aPort, rb, seenA, seenB),
                                                                     (rb, c.bPort, ra, seenB, seenA)] where seenHere {
                        let p = map.portPoint(room, port)
                        let v = CaveMap.vector(port)
                        let len = hypot(v.dx, v.dy)
                        let q = CGPoint(x: p.x + v.dx / len * 0.26, y: p.y + v.dy / len * 0.26)
                        Pencil.stroke(ctx, [toScreen(p), toScreen(q)], seed: seed &+ room.id,
                                      width: lineWidth, color: ink)
                        if detail {
                            let name = seenThere ? other.label : "?"
                            ctx.draw(Text("to " + name)
                                        .font(.custom(hand, size: 10.5 * min(max(zoom, 0.8), 1.5)))
                                        .foregroundColor(portalInk),
                                     at: toScreen(CGPoint(x: q.x + v.dx / len * 0.08, y: q.y + v.dy / len * 0.08)),
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
                    Pencil.stroke(ctx, Pencil.loop(center: center, rx: r, ry: r, seed: seed),
                                  seed: seed, width: lineWidth, color: ink)
                    continue
                }

                if seenA && seenB {
                    guard let pts = map.route(c)?.map(toScreen) else { continue }
                    Pencil.stroke(ctx, pts, seed: seed, width: lineWidth, color: ink)
                    if c.oneWay { drawArrow(ctx, pts: pts, toB: c.aToB, size: 0.07 * s, seed: seed) }
                    if detail {
                        // The command at each end, on opposite sides of the
                        // line so two tags never land on each other.
                        if !c.aTag.isEmpty { tags.append((c.aTag, pts[0], unit(pts[0], pts[1]), false)) }
                        if !c.bTag.isEmpty { tags.append((c.bTag, pts[3], unit(pts[3], pts[2]), true)) }
                    }
                } else if showStubs && ((seenA && c.aToB) || (seenB && c.bToA)) {
                    // An exit from a known room into the unknown.
                    let (room, port) = seenA ? (ra, c.aPort) : (rb, c.bPort)
                    let p = map.portPoint(room, port)
                    let v = CaveMap.vector(port)
                    let len = hypot(v.dx, v.dy)
                    let q = CGPoint(x: p.x + v.dx / len * 0.3, y: p.y + v.dy / len * 0.3)
                    Pencil.stroke(ctx, [toScreen(p), toScreen(q)], seed: seed &+ room.id,
                                  width: lineWidth, color: ink.opacity(0.7), dash: [3, 3])
                    if detail {
                        ctx.draw(Text("?").font(.custom(handBold, size: 12 * min(zoom, 1.4)))
                                    .foregroundColor(ink.opacity(0.7)),
                                 at: toScreen(CGPoint(x: q.x + v.dx / len * 0.07, y: q.y + v.dy / len * 0.07)))
                        let tag = seenA ? c.aTag : c.bTag
                        if !tag.isEmpty {
                            let a = toScreen(p)
                            tags.append((tag, a, unit(a, toScreen(q)), false))
                        }
                    }
                }
            }

            // Commands go on last, beside their lines just outside the box,
            // on a scrap of clean paper so no line ever runs through them.
            for tag in tags {
                let text = ctx.resolve(Text(tag.text)
                                        .font(.custom(hand, size: 10.5 * min(max(zoom, 0.8), 1.5)))
                                        .foregroundColor(wordInk))
                let size = text.measure(in: CGSize(width: 200, height: 40))
                let ux = tag.out.dx, uy = tag.out.dy
                // Along the line: far enough out that the text clears the box.
                let along = 3 + abs(ux) * size.width / 2 + abs(uy) * size.height / 2
                // Across the line: to one side, far enough to clear the line.
                var nx = -uy, ny = ux
                if ny > 0.2 || (abs(ny) <= 0.2 && nx < 0) { nx = -nx; ny = -ny }   // above / right
                if tag.flip { nx = -nx; ny = -ny }                                 // other end: below / left
                let clear = abs(nx) * (size.width / 2 + 3) + abs(ny) * (size.height / 2 + 1)
                let center = CGPoint(x: tag.at.x + ux * along + nx * clear,
                                     y: tag.at.y + uy * along + ny * clear)
                let backing = CGRect(x: center.x - size.width / 2 - 2, y: center.y - size.height / 2,
                                     width: size.width + 4, height: size.height)
                ctx.fill(Path(roundedRect: backing, cornerRadius: 3), with: .color(paper.opacity(0.92)))
                ctx.draw(text, at: center)
            }

            // Rooms
            let w = map.boxW * s, h = map.boxH * s
            for room in map.rooms where seen.contains(room.id) || room.id == current?.id {
                let c = toScreen(room.center)
                let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
                guard rect.intersects(CGRect(origin: .zero, size: canvasSize).insetBy(dx: -20, dy: -20))
                else { continue }
                let isHere = room.id == current?.id
                let isSelected = room.id == selected
                // Paper inside the box (the grid shows faintly through);
                // a yellow highlighter wash when the room is selected.
                ctx.fill(Path(rect), with: .color(isSelected ? Color(red: 1, green: 0.93, blue: 0.45).opacity(0.55)
                                                            : paper.opacity(0.8)))
                Pencil.box(ctx, rect, seed: room.id, width: isHere ? 2.0 : 1.3, color: ink)
                if detail {
                    let size = 10.5 * min(max(zoom, 0.85), 1.7)
                    // In the dark, an unseen room's name stays a mystery.
                    let label = seen.contains(room.id) ? room.label : "?"
                    let lines = wrapLabel(label, maxWidth: w - 8, ctx: ctx, size: size, bold: isHere)
                    let lineH = size * 1.12
                    let top = c.y - lineH * CGFloat(lines.count - 1) / 2
                    for (i, line) in lines.enumerated() {
                        ctx.draw(line, at: CGPoint(x: c.x, y: top + lineH * CGFloat(i)))
                    }
                }
            }

            let hereSeen = current.map({ seen.contains($0.id) }) ?? false
            if engine.isDark && !hereSeen {
                ctx.draw(Text("It is pitch dark. You can't see where you are.")
                            .font(.custom(handBold, size: 14))
                            .foregroundColor(here),
                         at: CGPoint(x: canvasSize.width / 2, y: 22))
            }

            if seen.isEmpty {
                ctx.draw(Text("Nothing explored yet.")
                            .font(.custom(hand, size: 16))
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
            // A red-pencil ring, drawn round twice like a quick hand would.
            let grow = 1 + CGFloat(pulse) * 0.05
            let rx = (w / 2 + 9) * grow, ry = (h / 2 + 8) * grow
            let ring = Pencil.loop(center: c, rx: rx, ry: ry, seed: me.id, turns: 1.15)
            Pencil.stroke(ctx, ring, seed: me.id, width: 2.2, color: here.opacity(0.9 - pulse * 0.3))
            let note = ctx.resolve(Text("you are here")
                                    .font(.custom(handBold, size: 13))
                                    .foregroundColor(here))
            let size = note.measure(in: CGSize(width: 200, height: 40))
            let at = CGPoint(x: c.x, y: c.y - ry - size.height / 2 - 2)
            ctx.fill(Path(roundedRect: CGRect(x: at.x - size.width / 2 - 3, y: at.y - size.height / 2,
                                              width: size.width + 6, height: size.height), cornerRadius: 3),
                     with: .color(paper.opacity(0.85)))
            ctx.draw(note, at: at)
        }
    }

    /// Unit vector from a to b (zero if they coincide).
    private func unit(_ a: CGPoint, _ b: CGPoint) -> CGVector {
        let d = hypot(b.x - a.x, b.y - a.y)
        return d > 0.001 ? CGVector(dx: (b.x - a.x) / d, dy: (b.y - a.y) / d) : CGVector(dx: 0, dy: -1)
    }

    /// Greedy word wrap into at most three centred lines.
    private func wrapLabel(_ label: String, maxWidth: CGFloat, ctx: GraphicsContext,
                           size: CGFloat, bold: Bool) -> [GraphicsContext.ResolvedText] {
        func resolve(_ s: String) -> GraphicsContext.ResolvedText {
            ctx.resolve(Text(s)
                .font(.custom(bold ? handBold : hand, size: size))
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

    /// A pencilled chevron halfway along a one-way passage.
    private func drawArrow(_ ctx: GraphicsContext, pts: [CGPoint], toB: Bool, size: CGFloat, seed: Int) {
        var a = pts[1], b = pts[2]
        if !toB { swap(&a, &b) }
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let ang = atan2(b.y - a.y, b.x - a.x)
        let tip = CGPoint(x: mid.x + cos(ang) * size * 0.6, y: mid.y + sin(ang) * size * 0.6)
        let left = CGPoint(x: tip.x + cos(ang + 2.6) * size, y: tip.y + sin(ang + 2.6) * size)
        let right = CGPoint(x: tip.x + cos(ang - 2.6) * size, y: tip.y + sin(ang - 2.6) * size)
        Pencil.stroke(ctx, [left, tip, right], seed: seed &+ 5, width: 1.6, color: ink)
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
                Text(room.label).font(.custom(handBold, size: 18))
                Spacer()
                Button {
                    withAnimation(.snappy) { selected = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(pencil)
                }
                .accessibilityLabel("Close")
            }
            if rows.isEmpty {
                Text("No known way out.").font(.custom(hand, size: 14))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(rows.indices, id: \.self) { i in
                        let row = rows[i]
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(row.0)
                                .font(.custom(handBold, size: 14))
                                .foregroundStyle(wordInk)
                            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(pencil)
                            Text(row.1).font(.custom(hand, size: 14))
                            if row.2 {
                                Text("(sometimes)").font(.custom(hand, size: 12)).foregroundStyle(pencil)
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

/// Hand-drawn pencil strokes. The wobble comes from a hash of a seed, not
/// a random generator, so every line looks the same each time the map is
/// redrawn instead of shimmering.
enum Pencil {
    /// Deterministic noise in -0.5…0.5.
    static func noise(_ seed: Int, _ i: Int) -> CGFloat {
        var h = UInt64(truncatingIfNeeded: seed &* 73_856_093 ^ i &* 19_349_663 ^ 0x5bd1e995)
        h ^= h >> 33
        h = h &* 0xff51_afd7_ed55_8ccd
        h ^= h >> 33
        h = h &* 0xc4ce_b9fe_1a85_ec53
        h ^= h >> 33
        return CGFloat(h % 10_000) / 10_000 - 0.5
    }

    /// A slightly wavering path through the points.
    static func path(_ pts: [CGPoint], seed: Int, wobble: CGFloat, step: CGFloat = 16) -> Path {
        var path = Path()
        guard pts.count > 1 else { return path }
        path.move(to: pts[0])
        var k = 0
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            let len = hypot(b.x - a.x, b.y - a.y)
            guard len > 0.01 else { continue }
            let nx = -(b.y - a.y) / len, ny = (b.x - a.x) / len
            let n = max(1, Int(len / step))
            for j in 1...n {
                let t = CGFloat(j) / CGFloat(n)
                let last = j == n
                let off = last ? noise(seed, 10_000 + i) * wobble * 0.4 : noise(seed, k) * wobble
                k += 1
                path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * t + nx * off,
                                         y: a.y + (b.y - a.y) * t + ny * off))
            }
        }
        return path
    }

    /// Pencil line: a firm stroke plus a fainter second pass beside it, the
    /// way graphite catches the paper's grain.
    static func stroke(_ ctx: GraphicsContext, _ pts: [CGPoint], seed: Int, width: CGFloat,
                       color: Color, dash: [CGFloat] = []) {
        ctx.stroke(path(pts, seed: seed, wobble: 1.3), with: .color(color.opacity(0.85)),
                   style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))
        ctx.stroke(path(pts, seed: seed &+ 7_919, wobble: 2.0), with: .color(color.opacity(0.22)),
                   style: StrokeStyle(lineWidth: width * 0.7, lineCap: .round, lineJoin: .round, dash: dash))
    }

    /// A box drawn as four separate strokes that overshoot the corners a
    /// little, as hand-ruled boxes do.
    static func box(_ ctx: GraphicsContext, _ r: CGRect, seed: Int, width: CGFloat, color: Color) {
        let o: CGFloat = 2.5
        let sides: [[CGPoint]] = [
            [CGPoint(x: r.minX - o, y: r.minY), CGPoint(x: r.maxX + o * 0.6, y: r.minY)],
            [CGPoint(x: r.maxX, y: r.minY - o * 0.6), CGPoint(x: r.maxX, y: r.maxY + o)],
            [CGPoint(x: r.maxX + o * 0.4, y: r.maxY), CGPoint(x: r.minX - o, y: r.maxY)],
            [CGPoint(x: r.minX, y: r.maxY + o * 0.5), CGPoint(x: r.minX, y: r.minY - o)],
        ]
        for (i, side) in sides.enumerated() {
            stroke(ctx, side, seed: seed &* 4 &+ i, width: width, color: color)
        }
    }

    /// Points round an ellipse, with a little irregularity; `turns` above 1
    /// carries the line past its start, like a circle drawn in one go.
    static func loop(center: CGPoint, rx: CGFloat, ry: CGFloat, seed: Int, turns: CGFloat = 1.08) -> [CGPoint] {
        let steps = 40
        var pts: [CGPoint] = []
        let start = noise(seed, 99) * .pi
        for i in 0...steps {
            let t = start + CGFloat(i) / CGFloat(steps) * 2 * .pi * turns
            let wob = 1 + noise(seed, 200 + i % 9) * 0.06
            pts.append(CGPoint(x: center.x + cos(t) * rx * wob, y: center.y + sin(t) * ry * wob))
        }
        return pts
    }
}
