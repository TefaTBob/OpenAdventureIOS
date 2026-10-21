import CoreGraphics
import Foundation

/// The cave's geography, generated from the game's own travel table by
/// Tools/make_map.py (see Tools/map_layout.txt for room positions).
///
/// Positions are in grid units; a room box is `boxW` × `boxH` units.
/// Room ids are engine LOC_* indices; `locs` lists every engine location
/// shown by that box (the dragon's canyon is three locations, for example).
final class CaveMap: Sendable {
    struct Exit: Decodable, Sendable {
        let to: Int
        let words: [String]
        let conditional: Bool
    }

    struct Room: Decodable, Identifiable, Sendable {
        let id: Int
        let locs: [Int]
        let label: String
        let region: String
        let x: Double
        let y: Double
        let exits: [Exit]

        var center: CGPoint { CGPoint(x: x, y: y) }
    }

    /// One drawn line. Ports are compass sides of the box (n, ne, … nw).
    struct Connection: Decodable, Sendable {
        let a: Int
        let b: Int
        let aPort: String
        let bPort: String
        let aLabel: String
        let bLabel: String
        let aToB: Bool
        let bToA: Bool
        /// Drawn as a labelled stub at each end ("to Twisty Maze 1")
        /// instead of a line across the map.
        let portal: Bool
        /// The one word written beside the line ("up", "over", …) and the
        /// end ("a" or "b") you travel from; empty when the line says it all.
        let label: String
        let labelEnd: String
        /// The command you type at each end ("N", "NE", "W/U", "IN", "climb");
        /// empty for an end you can't leave by (one-way passages).
        let aTag: String
        let bTag: String

        var isLoop: Bool { a == b }
        var oneWay: Bool { aToB != bToA }
    }

    struct Region: Decodable, Sendable {
        let region: String
        let title: String
        let x0: Double, y0: Double, x1: Double, y1: Double
    }

    private struct Box: Decodable { let w: Double; let h: Double }
    private struct Bounds: Decodable { let x0: Double; let y0: Double; let x1: Double; let y1: Double }
    private struct File: Decodable {
        let box: Box
        let bounds: Bounds
        let rooms: [Room]
        let connections: [Connection]
        let regions: [Region]
    }

    static let shared = CaveMap()

    let boxW: Double
    let boxH: Double
    let bounds: CGRect
    let rooms: [Room]
    let connections: [Connection]
    let regions: [Region]
    private let byID: [Int: Room]
    private let byLocation: [Int: Room]

    private init() {
        let file: File?
        if let url = Bundle.main.url(forResource: "cave_map", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            file = try? JSONDecoder().decode(File.self, from: data)
        } else {
            file = nil
        }
        boxW = file?.box.w ?? 0.74
        boxH = file?.box.h ?? 0.52
        if let b = file?.bounds {
            bounds = CGRect(x: b.x0, y: b.y0, width: b.x1 - b.x0, height: b.y1 - b.y0)
        } else {
            bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        rooms = file?.rooms ?? []
        connections = file?.connections ?? []
        regions = file?.regions ?? []
        byID = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
        var locs: [Int: Room] = [:]
        for room in rooms {
            for loc in room.locs { locs[loc] = room }
        }
        byLocation = locs
    }

    func room(_ id: Int) -> Room? { byID[id] }

    /// The box showing an engine location (several locations can share one).
    func room(forLocation loc: Int) -> Room? { byLocation[loc] }

    var mappableCount: Int { rooms.count }

    /// Unit vector for a port name, y growing downward (south).
    static func vector(_ port: String) -> CGVector {
        switch port {
        case "n": CGVector(dx: 0, dy: -1)
        case "s": CGVector(dx: 0, dy: 1)
        case "e": CGVector(dx: 1, dy: 0)
        case "w": CGVector(dx: -1, dy: 0)
        case "ne": CGVector(dx: 1, dy: -1)
        case "nw": CGVector(dx: -1, dy: -1)
        case "se": CGVector(dx: 1, dy: 1)
        case "sw": CGVector(dx: -1, dy: 1)
        default: CGVector(dx: 0, dy: -1)
        }
    }

    /// Where a port sits on a room's box, in grid units.
    func portPoint(_ room: Room, _ port: String) -> CGPoint {
        let v = Self.vector(port)
        return CGPoint(x: room.x + v.dx * boxW / 2, y: room.y + v.dy * boxH / 2)
    }

    /// The polyline for a connection: out of each port a short way, then
    /// straight across — the same routing the generator's checks assume.
    func route(_ c: Connection, stub: Double = 0.16) -> [CGPoint]? {
        guard let ra = room(c.a), let rb = room(c.b) else { return nil }
        let p = portPoint(ra, c.aPort), q = portPoint(rb, c.bPort)
        let va = Self.vector(c.aPort), vb = Self.vector(c.bPort)
        let la = hypot(va.dx, va.dy), lb = hypot(vb.dx, vb.dy)
        let p2 = CGPoint(x: p.x + va.dx / la * stub, y: p.y + va.dy / la * stub)
        let q2 = CGPoint(x: q.x + vb.dx / lb * stub, y: q.y + vb.dy / lb * stub)
        return [p, p2, q2, q]
    }
}
