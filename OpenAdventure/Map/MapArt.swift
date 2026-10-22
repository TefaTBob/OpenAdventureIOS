import SwiftUI

/// The map's pen-and-ink layer, baked by Tools/make_art.py into
/// map_art.json: chamber outlines, tunnel walls, rock hatching, the sketch
/// of each place and the items found there, and terrain marks round about.
///
/// Everything is in points at zoom 1 (`unit` points per grid unit), so the
/// map view draws it with one scale-and-translate. Strokes that share a
/// colour, width and dash are merged into one path when the file loads.
final class MapArt: @unchecked Sendable {
    enum Ink: Int, CaseIterable {
        case ink, soft, blue, red, green, gold, brown

        var color: Color {
            switch self {
            case .ink: Color(red: 0.13, green: 0.12, blue: 0.12)
            case .soft: Color(red: 0.43, green: 0.40, blue: 0.38)
            case .blue: Color(red: 0.20, green: 0.36, blue: 0.59)
            case .red: Color(red: 0.75, green: 0.24, blue: 0.16)
            case .green: Color(red: 0.24, green: 0.47, blue: 0.27)
            case .gold: Color(red: 0.72, green: 0.53, blue: 0.16)
            case .brown: Color(red: 0.51, green: 0.35, blue: 0.22)
            }
        }
    }

    /// Strokes of one style, merged.
    struct Group {
        let ink: Ink
        let width: CGFloat
        let dash: [CGFloat]
        let path: Path
    }

    struct Label {
        let text: String
        let at: CGPoint
        let size: CGFloat
        let rotation: Angle
        let ink: Ink
        let bold: Bool
    }

    struct Symbol {
        let groups: [Group]
        let bounds: CGRect
    }

    /// A carryable thing, drawn on its own: in the inventory, and on the
    /// map wherever you last saw it lying.
    struct ItemArt {
        let groups: [Group]
        let labels: [Label]
        let bounds: CGRect
        let caption: String
    }

    /// A creature drawn beside its room, shown only while you last saw
    /// that object there.
    struct Part {
        let object: Int
        let groups: [Group]
        let labels: [Label]
    }

    struct Mark {
        let symbol: Int
        let at: CGPoint
    }

    struct RoomArt {
        let surface: Bool
        let outline: Path
        let fill: Path
        let hatch: [Group]
        let art: [Group]
        let labels: [Label]
        let marks: [Mark]
        let parts: [Part]
        /// Clear spots round the room (centres) where things lying here are
        /// drawn, nearest first.
        let slots: [CGPoint]
        /// Everything this room draws, for skipping rooms off screen.
        let bounds: CGRect
    }

    /// A short tunnel out of one end of a passage: shown while the far end
    /// is unexplored, or as an off-page stub.
    struct End {
        let walls: Path
        let fill: Path
        let tip: CGPoint
    }

    struct PassageArt {
        let walls: Path?
        let fill: Path?
        let hatch: [Group]
        let trail: Path?
        let ends: [End]
        let bounds: CGRect
    }

    static let shared = MapArt()

    /// Points per grid unit at zoom 1.
    let unit: CGFloat
    /// Half the width of a tunnel, in points at zoom 1.
    let tunnelHalfWidth: CGFloat
    let symbols: [Symbol]
    let rooms: [Int: RoomArt]
    /// Same order as CaveMap.connections.
    let passages: [PassageArt]
    /// Inventory sketches by engine object index.
    let items: [Int: ItemArt]
    /// Size of an item slot, in points at zoom 1.
    let slotSize: CGSize
    /// Engine object indices the map treats specially.
    let dwarf: Int, water: Int, oil: Int, rug: Int, dragon: Int, bear: Int

    private init() {
        var unit: CGFloat = 128, tunnel: CGFloat = 5
        var symbols: [Symbol] = []
        var rooms: [Int: RoomArt] = [:]
        var passages: [PassageArt] = []
        var items: [Int: ItemArt] = [:]
        var slotSize = CGSize(width: 34, height: 36)
        var special: [String: Int] = [:]
        if let url = Bundle.main.url(forResource: "map_art", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let scale = CGFloat(Self.num(doc["scale"]) ?? 10)
            unit = CGFloat(Self.num(doc["unit"]) ?? 128)
            tunnel = CGFloat(Self.num(doc["tunnel"]) ?? 5)
            let reader = Reader(scale: scale)

            for case let s as [String: Any] in doc["symbols"] as? [Any] ?? [] {
                let strokes = s["strokes"] as? [Any] ?? []
                symbols.append(Symbol(groups: reader.groups(strokes), bounds: reader.bounds(strokes)))
            }
            for case let r as [String: Any] in doc["rooms"] as? [Any] ?? [] {
                guard let id = Self.num(r["id"]).map(Int.init) else { continue }
                let marks: [Mark] = (r["marks"] as? [Any] ?? []).compactMap { m in
                    guard let a = m as? [Any], a.count == 3, let s = Self.num(a[0]),
                          let x = Self.num(a[1]), let y = Self.num(a[2]) else { return nil }
                    return Mark(symbol: Int(s), at: CGPoint(x: CGFloat(x) / scale, y: CGFloat(y) / scale))
                }
                let outlinePts = reader.points(r["outline"])
                let hatch = r["hatch"] as? [Any] ?? []
                let art = r["art"] as? [Any] ?? []
                var box = Reader.box(outlinePts).union(reader.bounds(hatch)).union(reader.bounds(art))
                for m in marks where symbols.indices.contains(m.symbol) {
                    box = box.union(symbols[m.symbol].bounds.offsetBy(dx: m.at.x, dy: m.at.y))
                }
                let labels = (r["text"] as? [Any] ?? []).compactMap { reader.label($0) }
                for l in labels {
                    box = box.union(CGRect(x: l.at.x - 40, y: l.at.y - 10, width: 80, height: 20))
                }
                let parts: [Part] = (r["parts"] as? [Any] ?? []).compactMap { v in
                    guard let p = v as? [String: Any], let obj = Self.num(p["obj"]) else { return nil }
                    let strokes = p["strokes"] as? [Any] ?? []
                    box = box.union(reader.bounds(strokes))
                    return Part(object: Int(obj), groups: reader.groups(strokes),
                                labels: (p["text"] as? [Any] ?? []).compactMap { reader.label($0) })
                }
                let slots = reader.points((r["slots"] as? [Any] ?? []).flatMap { $0 as? [Any] ?? [] })
                for c in slots {
                    box = box.union(CGRect(x: c.x - 20, y: c.y - 20, width: 40, height: 40))
                }
                rooms[id] = RoomArt(surface: (r["kind"] as? String) == "surface",
                                    outline: Reader.polygon(outlinePts),
                                    fill: Reader.polygon(reader.points(r["fill"])),
                                    hatch: reader.groups(hatch),
                                    art: reader.groups(art),
                                    labels: labels,
                                    marks: marks,
                                    parts: parts,
                                    slots: slots,
                                    bounds: box)
            }
            for case let c as [String: Any] in doc["connections"] as? [Any] ?? [] {
                var walls: Path?
                var box = CGRect.null
                if let ws = c["walls"] as? [Any] {
                    var p = Path()
                    for w in ws {
                        let pts = reader.points(w)
                        p.addLines(pts)
                        box = box.union(Reader.box(pts))
                    }
                    walls = p
                }
                let fill = c["fill"].map { Reader.polygon(reader.points($0)) }
                let trailPts = c["trail"].map { reader.points($0) }
                if let t = trailPts { box = box.union(Reader.box(t)) }
                let hatch = c["hatch"] as? [Any] ?? []
                box = box.union(reader.bounds(hatch))
                let ends: [End] = (c["ends"] as? [Any] ?? []).compactMap { e in
                    guard let e = e as? [String: Any] else { return nil }
                    var p = Path()
                    for w in e["walls"] as? [Any] ?? [] {
                        let pts = reader.points(w)
                        p.addLines(pts)
                        box = box.union(Reader.box(pts))
                    }
                    return End(walls: p, fill: Reader.polygon(reader.points(e["fill"])),
                               tip: reader.points(e["tip"]).first ?? .zero)
                }
                passages.append(PassageArt(walls: walls, fill: fill, hatch: reader.groups(hatch),
                                           trail: trailPts.map { var p = Path(); p.addLines($0); return p },
                                           ends: ends, bounds: box))
            }
            for (key, value) in doc["items"] as? [String: Any] ?? [:] {
                guard let id = Int(key), let item = value as? [String: Any] else { continue }
                let strokes = item["strokes"] as? [Any] ?? []
                items[id] = ItemArt(groups: reader.groups(strokes),
                                    labels: (item["text"] as? [Any] ?? []).compactMap { reader.label($0) },
                                    bounds: reader.bounds(strokes),
                                    caption: item["caption"] as? String ?? "")
            }
            if let s = doc["slot"] as? [Any], s.count == 2, let w = Self.num(s[0]), let h = Self.num(s[1]) {
                slotSize = CGSize(width: CGFloat(w) / scale, height: CGFloat(h) / scale)
            }
            for (k, v) in doc["objects"] as? [String: Any] ?? [:] {
                if let n = Self.num(v) { special[k] = Int(n) }
            }
        }
        self.unit = unit
        self.tunnelHalfWidth = tunnel
        self.symbols = symbols
        self.rooms = rooms
        self.passages = passages
        self.items = items
        self.slotSize = slotSize
        dwarf = special["dwarf"] ?? 17
        water = special["water"] ?? 21
        oil = special["oil"] ?? 22
        rug = special["rug"] ?? 62
        dragon = special["dragon"] ?? 31
        bear = special["bear"] ?? 35
    }

    fileprivate static func num(_ v: Any?) -> Double? {
        (v as? NSNumber)?.doubleValue
    }

    /// Turns the file's integer arrays into points and paths.
    private struct Reader {
        let scale: CGFloat

        func points(_ v: Any?) -> [CGPoint] {
            guard let a = v as? [Any] else { return [] }
            return points(a, from: 0)
        }

        func points(_ a: [Any], from start: Int) -> [CGPoint] {
            var out: [CGPoint] = []
            out.reserveCapacity((a.count - start) / 2)
            var i = start
            while i + 1 < a.count {
                out.append(CGPoint(x: CGFloat(MapArt.num(a[i]) ?? 0) / scale,
                                   y: CGFloat(MapArt.num(a[i + 1]) ?? 0) / scale))
                i += 2
            }
            return out
        }

        /// Strokes are [colour, width, dash on, dash off, x, y, x, y…].
        func groups(_ strokes: [Any]) -> [Group] {
            struct Key: Hashable { let ink: Int; let w: Int; let on: Int; let off: Int }
            var paths: [Key: Path] = [:]
            var order: [Key] = []
            for case let s as [Any] in strokes where s.count >= 8 {
                let key = Key(ink: Int(MapArt.num(s[0]) ?? 0), w: Int(MapArt.num(s[1]) ?? 10),
                              on: Int(MapArt.num(s[2]) ?? 0), off: Int(MapArt.num(s[3]) ?? 0))
                if paths[key] == nil { order.append(key); paths[key] = Path() }
                paths[key]?.addLines(points(s, from: 4))
            }
            return order.map { k in
                Group(ink: Ink(rawValue: k.ink) ?? .ink, width: CGFloat(k.w) / scale,
                      dash: k.on > 0 ? [CGFloat(k.on) / scale, CGFloat(k.off) / scale] : [],
                      path: paths[k] ?? Path())
            }
        }

        func bounds(_ strokes: [Any]) -> CGRect {
            var box = CGRect.null
            for case let s as [Any] in strokes where s.count >= 6 {
                box = box.union(Self.box(points(s, from: 4)))
            }
            return box
        }

        /// [text, x, y, size, rotation, colour, bold]
        func label(_ v: Any) -> Label? {
            guard let a = v as? [Any], a.count >= 7, let text = a[0] as? String else { return nil }
            func n(_ i: Int) -> CGFloat { CGFloat(MapArt.num(a[i]) ?? 0) / scale }
            return Label(text: text, at: CGPoint(x: n(1), y: n(2)), size: n(3),
                         rotation: .degrees(Double(n(4))),
                         ink: Ink(rawValue: Int(MapArt.num(a[5]) ?? 0)) ?? .ink,
                         bold: (MapArt.num(a[6]) ?? 0) != 0)
        }

        static func polygon(_ pts: [CGPoint]) -> Path {
            var p = Path()
            p.addLines(pts)
            p.closeSubpath()
            return p
        }

        static func box(_ pts: [CGPoint]) -> CGRect {
            guard let f = pts.first else { return .null }
            var x0 = f.x, y0 = f.y, x1 = f.x, y1 = f.y
            for p in pts {
                x0 = min(x0, p.x); y0 = min(y0, p.y); x1 = max(x1, p.x); y1 = max(y1, p.y)
            }
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
    }
}
