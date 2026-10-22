import Foundation

/// What we know about a save besides the engine's own binary file.
struct SaveMeta: Codable, Sendable {
    var date: Date
    var room: String
    var score: Int
    var turns: Int
    /// Rooms seen, so the map comes back exactly as it was.
    var visited: [Int]
    /// What you last saw lying in each place (location → object indices),
    /// for the map. Missing in saves from before the map showed items.
    var items: [String: [Int]]? = nil
}

/// Save files live in Documents/Saves, visible in the Files app.
///
/// Each slot is `<id>.adv` (the engine's native format, identical to the
/// desktop game's) plus `<id>.json` metadata. Saves made with the in-game
/// SAVE command land in the same folder under whatever name was typed.
@MainActor
final class SaveStore {
    static let autosaveID = "autosave"
    static let slotIDs = (1...6).map { "slot\($0)" }

    let directory: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = docs.appendingPathComponent("Saves", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func fileURL(for id: String) -> URL {
        if Self.isManaged(id) {
            return directory.appendingPathComponent(id + ".adv")
        }
        return directory.appendingPathComponent(id) // typed in-game name, as-is
    }

    private func metaURL(for id: String) -> URL {
        directory.appendingPathComponent(id + ".json")
    }

    func exists(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: id).path)
    }

    func meta(for id: String) -> SaveMeta? {
        guard let data = try? Data(contentsOf: metaURL(for: id)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SaveMeta.self, from: data)
    }

    func modificationDate(for id: String) -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL(for: id).path)
        return attrs?[.modificationDate] as? Date
    }

    /// Writes the engine state (only possible while it waits for input).
    func write(id: String, meta: SaveMeta) -> Bool {
        let url = fileURL(for: id)
        let ok = url.path.withCString { advent_save($0) }
        guard ok else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(meta) {
            try? data.write(to: metaURL(for: id), options: .atomic)
        }
        return true
    }

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
        try? FileManager.default.removeItem(at: metaURL(for: id))
    }

    /// Saves made with the in-game SAVE command (any name the player typed).
    func typedSaves() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { name in
                !name.hasSuffix(".json") && !name.hasPrefix(".")
                    && !Self.isManaged(String(name.dropLast(4)))
            }
            .sorted()
    }

    private static func isManaged(_ id: String) -> Bool {
        id == autosaveID || slotIDs.contains(id)
    }
}
