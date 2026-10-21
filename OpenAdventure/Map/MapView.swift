import SwiftUI

/// The explorer's map, sketched in pen and ink in a notebook.
///
/// - Places appear once you've seen them (lit): caves as chambers joined by
///   tunnels, the surface as clearings joined by trails. Passages leave each
///   room from the side matching the exit's direction, so "north" really is
///   the top. Beside each end is the command that takes you along it, the
///   game's way: N, NE, U, IN… ("N/D" when both work).
/// - Round each place is a sketch of what the game describes there and the
///   things lying there when the game starts, plus rocks, trees or water.
///   The drawings come from map_art.json (see Tools/make_art.py).
/// - Arrowheads mark one-way passages. Short dashed stubs are exits you
///   haven't followed yet.
/// - The pulsing red ring is you.
/// - The backpack button lists what you're carrying.
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
    @State private var showInventory = false

    private let map = CaveMap.shared
    private let art = MapArt.shared
    /// Points per grid unit at zoom 1.
    private var unit: CGFloat { art.unit }

    /// Sketchbook paper and the ink on it.
    private let paper = Color(red: 0.965, green: 0.945, blue: 0.898)
    private let ink = MapArt.Ink.ink.color
    private let pencil = MapArt.Ink.soft.color
    private let wordInk = Color(red: 0.27, green: 0.25, blue: 0.24)
    private let here = Color(red: 0.77, green: 0.16, blue: 0.13)   // red pencil
    /// How a passage shows: as a tunnel (or trail), a stub out of the one
    /// end you've seen, off-page stubs, or not at all.
    private enum Show { case tunnel, stub(Int), portal([Int]), none }

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
        .sheet(isPresented: $showInventory) {
            InventoryView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
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
                showInventory = true
            } label: {
                Image(systemName: "backpack")
            }
            .accessibilityLabel("Inventory")
            .padding(.trailing, 16)
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
        let z = zoom
        let showStubs = settings.showUnexploredExits
        let seen = Set(map.rooms.filter(isSeen).map(\.id))
        let current = map.room(forLocation: engine.location)
        let detail = zoom >= 0.55
        let fine = zoom >= 0.4          // hatching and terrain marks
        let selectedID = selected
        // Art is in points at zoom 1; this puts it on screen.
        let origin = toScreen(.zero)
        let artToScreen = CGAffineTransform(a: z, b: 0, c: 0, d: z, tx: origin.x, ty: origin.y)
        // Pen widths grow with zoom, but less than the drawing does.
        let pen = min(max(z, 0.55), 1.5)

        return Canvas { ctx, canvasSize in
            let screen = CGRect(origin: .zero, size: canvasSize).insetBy(dx: -30, dy: -30)
            let visible = screen.applying(artToScreen.inverted())

            // One context drawing in art coordinates.
            var ink = ctx
            ink.concatenate(artToScreen)
            func stroke(_ path: Path, _ color: Color, _ width: CGFloat, dash: [CGFloat] = []) {
                ink.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: width * pen / z, lineCap: .round, lineJoin: .round,
                                              dash: dash))
            }
            func draw(_ groups: [MapArt.Group], in c: GraphicsContext? = nil) {
                let g = c ?? ink
                for group in groups {
                    g.stroke(group.path, with: .color(group.ink.color),
                             style: StrokeStyle(lineWidth: group.width * pen / z, lineCap: .round,
                                                lineJoin: .round, dash: group.dash))
                }
            }

            // Which passages show, and how.
            var shows: [(CaveMap.Connection, MapArt.PassageArt, Show)] = []
            for (i, c) in map.connections.enumerated() where i < art.passages.count {
                let pa = art.passages[i]
                guard pa.bounds.isNull || pa.bounds.intersects(visible) else { continue }
                let sa = seen.contains(c.a), sb = seen.contains(c.b)
                let show: Show
                if c.portal {
                    let ends = [sa ? 0 : nil, sb ? 1 : nil].compactMap { $0 }
                    show = ends.isEmpty ? .none : .portal(ends)
                } else if c.isLoop {
                    show = .none
                } else if sa && sb {
                    show = .tunnel
                } else if showStubs && ((sa && c.aToB) || (sb && c.bToA)) {
                    show = .stub(sa ? 0 : 1)
                } else {
                    show = .none
                }
                shows.append((c, pa, show))
            }
            func surface(_ id: Int) -> Bool { art.rooms[id]?.surface ?? false }
            let roomsShown = map.rooms.filter { room in
                (seen.contains(room.id) || room.id == current?.id)
                    && (art.rooms[room.id]?.bounds.intersects(visible) ?? true)
            }

            // 1. Walls: tunnels, stubs and chamber outlines.
            for (c, pa, show) in shows {
                switch show {
                case .tunnel:
                    if let w = pa.walls { stroke(w, MapArt.Ink.ink.color, 1.15) }
                case .stub(let end):
                    if !surface(end == 0 ? c.a : c.b), pa.ends.indices.contains(end) {
                        stroke(pa.ends[end].walls, MapArt.Ink.ink.color.opacity(0.8), 1.15, dash: [4, 3])
                    }
                case .portal(let ends):
                    for e in ends where pa.ends.indices.contains(e) {
                        stroke(pa.ends[e].walls, MapArt.Ink.ink.color, 1.15)
                    }
                case .none: break
                }
            }
            for room in roomsShown {
                guard let ra = art.rooms[room.id] else { continue }
                if ra.surface {
                    stroke(ra.outline, MapArt.Ink.soft.color, 1.1, dash: [5, 3])
                } else {
                    stroke(ra.outline, MapArt.Ink.ink.color, room.id == current?.id ? 1.9 : 1.5)
                }
            }

            // 2. Clean paper inside tunnels and chambers opens the walls
            //    where a passage meets a room.
            for (c, pa, show) in shows {
                switch show {
                case .tunnel:
                    if let f = pa.fill { ink.fill(f, with: .color(paper)) }
                case .stub(let end):
                    if !surface(end == 0 ? c.a : c.b), pa.ends.indices.contains(end) {
                        ink.fill(pa.ends[end].fill, with: .color(paper))
                    }
                case .portal(let ends):
                    for e in ends where pa.ends.indices.contains(e) { ink.fill(pa.ends[e].fill, with: .color(paper)) }
                case .none: break
                }
            }
            for room in roomsShown {
                guard let ra = art.rooms[room.id] else { continue }
                if room.id == selectedID {
                    ink.fill(ra.fill, with: .color(Color(red: 1, green: 0.93, blue: 0.45).opacity(0.55)))
                } else if !ra.surface {
                    ink.fill(ra.fill, with: .color(paper))
                }
            }

            // 3. Trails above ground, loops, one-way arrows, hatching.
            let lineWidth = max(1, 1.2 * pen)
            var tags: [(text: String, at: CGPoint, out: CGVector, flip: Bool, outdoor: Bool)] = []
            for (c, pa, show) in shows {
                guard let ra = map.room(c.a), let rb = map.room(c.b) else { continue }
                let seed = c.a &* 1009 &+ c.b
                switch show {
                case .tunnel:
                    if let t = pa.trail { stroke(t, MapArt.Ink.soft.color, 1.0, dash: [4, 3]) }
                    if fine { draw(pa.hatch) }
                    guard let pts = map.route(c)?.map(toScreen) else { continue }
                    if c.oneWay { drawArrow(ctx, pts: pts, toB: c.aToB, size: 0.045 * s, seed: seed) }
                    if detail {
                        let outdoor = pa.trail != nil
                        if !c.aTag.isEmpty { tags.append((c.aTag, pts[0], direction(pts[0], pts[1]), false, outdoor)) }
                        if !c.bTag.isEmpty { tags.append((c.bTag, pts[3], direction(pts[3], pts[2]), true, outdoor)) }
                    }
                case .stub(let end):
                    let (room, port) = end == 0 ? (ra, c.aPort) : (rb, c.bPort)
                    let p = toScreen(map.portPoint(room, port))
                    if surface(room.id), pa.ends.indices.contains(end) {
                        var trail = Path()
                        trail.move(to: p)
                        trail.addLine(to: pa.ends[end].tip.applying(artToScreen))
                        ctx.stroke(trail, with: .color(MapArt.Ink.soft.color),
                                   style: StrokeStyle(lineWidth: pen, lineCap: .round, dash: [3, 3]))
                    }
                    if detail {
                        let v = CaveMap.vector(port)
                        let len = hypot(v.dx, v.dy)
                        let q = map.portPoint(room, port)
                        ctx.draw(Text("?").font(.custom(handBold, size: 12 * min(z, 1.4)))
                                    .foregroundColor(MapArt.Ink.ink.color.opacity(0.75)),
                                 at: toScreen(CGPoint(x: q.x + v.dx / len * 0.36, y: q.y + v.dy / len * 0.36)))
                        let tag = end == 0 ? c.aTag : c.bTag
                        if !tag.isEmpty {
                            let tip = toScreen(CGPoint(x: q.x + v.dx / len * 0.3, y: q.y + v.dy / len * 0.3))
                            tags.append((tag, p, direction(p, tip), false, surface(room.id)))
                        }
                    }
                case .portal(let ends):
                    guard detail else { continue }
                    for e in ends {
                        let (room, port, other) = e == 0 ? (ra, c.aPort, rb) : (rb, c.bPort, ra)
                        let v = CaveMap.vector(port)
                        let len = hypot(v.dx, v.dy)
                        let q = map.portPoint(room, port)
                        let name = seen.contains(other.id) ? other.label : "?"
                        ctx.draw(Text("to " + name)
                                    .font(.custom(hand, size: 10.5 * min(max(z, 0.8), 1.5)))
                                    .foregroundColor(wordInk),
                                 at: toScreen(CGPoint(x: q.x + v.dx / len * 0.3, y: q.y + v.dy / len * 0.3)),
                                 anchor: v.dx > 0 ? .leading : (v.dx < 0 ? .trailing : .center))
                    }
                case .none:
                    if c.isLoop, seen.contains(c.a) {
                        let p = toScreen(map.portPoint(ra, c.aPort))
                        let v = CaveMap.vector(c.aPort)
                        let r = 0.07 * s
                        let center = CGPoint(x: p.x + v.dx * r, y: p.y + v.dy * r)
                        Pencil.stroke(ctx, Pencil.loop(center: center, rx: r, ry: r, seed: seed),
                                      seed: seed, width: lineWidth, color: MapArt.Ink.ink.color)
                    }
                }
            }

            // 4. The sketches: hatching round the walls, what's there, and
            //    the lie of the land.
            for room in roomsShown {
                guard let ra = art.rooms[room.id] else { continue }
                if fine {
                    draw(ra.hatch)
                    for m in ra.marks where art.symbols.indices.contains(m.symbol) {
                        let sym = art.symbols[m.symbol]
                        guard sym.bounds.offsetBy(dx: m.at.x, dy: m.at.y).intersects(visible) else { continue }
                        var c = ink
                        c.translateBy(x: m.at.x, y: m.at.y)
                        draw(sym.groups, in: c)
                    }
                }
                draw(ra.art)
                if detail {
                    for l in ra.labels {
                        var c = ink
                        c.translateBy(x: l.at.x, y: l.at.y)
                        c.rotate(by: l.rotation)
                        // Noteworthy runs wider than the tool's stand-in hand.
                        c.draw(Text(l.text)
                                .font(.custom(l.bold ? handBold : hand, size: l.size * 1.1))
                                .foregroundColor(l.ink.color),
                               at: .zero)
                    }
                }
            }

            // 5. Commands beside each end of a passage, on a scrap of
            //    clean paper, clear of the tunnel walls.
            let tunnelHalf = art.tunnelHalfWidth * z
            for tag in tags {
                let text = ctx.resolve(Text(tag.text)
                                        .font(.custom(hand, size: 10.5 * min(max(z, 0.8), 1.5)))
                                        .foregroundColor(wordInk))
                let size = text.measure(in: CGSize(width: 200, height: 40))
                let ux = tag.out.dx, uy = tag.out.dy
                let along = 4 + abs(ux) * size.width / 2 + abs(uy) * size.height / 2
                var nx = -uy, ny = ux
                if ny > 0.2 || (abs(ny) <= 0.2 && nx < 0) { nx = -nx; ny = -ny }   // above / right
                if tag.flip { nx = -nx; ny = -ny }                                 // other end: below / left
                let wall = tag.outdoor ? 3 : tunnelHalf + 1.5
                let clear = wall + abs(nx) * size.width / 2 + abs(ny) * size.height / 2
                let center = CGPoint(x: tag.at.x + ux * along + nx * clear,
                                     y: tag.at.y + uy * along + ny * clear)
                let backing = CGRect(x: center.x - size.width / 2 - 2, y: center.y - size.height / 2,
                                     width: size.width + 4, height: size.height)
                ctx.fill(Path(roundedRect: backing, cornerRadius: 3), with: .color(paper.opacity(0.9)))
                ctx.draw(text, at: center)
            }

            // 6. Names.
            if detail {
                let w = map.boxW * s
                for room in roomsShown {
                    let c = toScreen(room.center)
                    let size = 10.5 * min(max(z, 0.85), 1.7)
                    let label = seen.contains(room.id) ? room.label : "?"
                    let lines = wrapLabel(label, maxWidth: w - 6, ctx: ctx, size: size, bold: room.id == current?.id)
                    let lineH = size * 1.12
                    let top = c.y - lineH * CGFloat(lines.count - 1) / 2
                    for (i, line) in lines.enumerated() {
                        ctx.draw(line, at: CGPoint(x: c.x, y: top + lineH * CGFloat(i)))
                    }
                }
            }

            compassRose(ctx, at: CGPoint(x: 34, y: canvasSize.height - 40))

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

    /// A small hand-drawn compass in the corner: north is up.
    private func compassRose(_ ctx: GraphicsContext, at c: CGPoint) {
        let r: CGFloat = 17
        let color = MapArt.Ink.ink.color
        Pencil.stroke(ctx, [CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x, y: c.y - r)], seed: 901, width: 1, color: color)
        Pencil.stroke(ctx, [CGPoint(x: c.x - r, y: c.y), CGPoint(x: c.x + r, y: c.y)], seed: 902, width: 1, color: color)
        Pencil.stroke(ctx, [CGPoint(x: c.x - 4, y: c.y - r + 6), CGPoint(x: c.x, y: c.y - r - 2),
                            CGPoint(x: c.x + 4, y: c.y - r + 6)], seed: 903, width: 1.1, color: color)
        Pencil.stroke(ctx, Pencil.loop(center: c, rx: r * 0.4, ry: r * 0.4, seed: 904), seed: 904,
                      width: 0.8, color: MapArt.Ink.soft.color)
        ctx.draw(Text("N").font(.custom(handBold, size: 11)).foregroundColor(color),
                 at: CGPoint(x: c.x, y: c.y - r - 10))
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
    private func direction(_ a: CGPoint, _ b: CGPoint) -> CGVector {
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
