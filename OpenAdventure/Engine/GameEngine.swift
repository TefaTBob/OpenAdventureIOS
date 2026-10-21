import Foundation
import Observation

/// Swift face of the C engine (Engine/shim/advent_bridge.h).
///
/// The upstream game runs on its own thread and blocks whenever it wants a
/// line of input. Its callbacks arrive on that thread; each one copies what
/// it needs and hops to the main queue, tagged with the game's generation so
/// that anything still queued from a stopped game is ignored.
@MainActor
@Observable
final class GameEngine {
    static let shared = GameEngine()

    /// Completed transcript lines; the last element is the line in progress.
    private(set) var lines: [String] = [""]
    /// Bumped whenever `lines` changes, so views can cache layout cheaply.
    private(set) var revision = 0
    /// Non-nil while the engine is waiting for a line of input.
    private(set) var prompt: String?
    /// What the player has typed so far on the current line.
    var input = ""

    private(set) var location = 1
    private(set) var visited: Set<Int> = []
    private(set) var isDark = false
    private(set) var score = 0
    private(set) var maxScore = 430
    private(set) var turns = 0
    private(set) var isOver = false
    /// What you're carrying, in the game's own words, as INVENTORY lists it.
    private(set) var carried: [CarriedItem] = []
    /// The tame bear is following you.
    private(set) var bearFollowing = false
    private(set) var askingFilename = false

    private var history: [String] = []
    private var historyCursor: Int?
    private var generation = 0
    private var callbackBox: CallbackBox?

    let saves = SaveStore()

    private init() {}

    // MARK: Lifecycle

    private var launched = false

    /// Resume the autosave if there is one, otherwise start fresh.
    func launch() {
        guard !launched else { return }
        launched = true
        if saves.exists(SaveStore.autosaveID) {
            load(SaveStore.autosaveID, banner: nil)
        } else {
            startNewGame()
        }
    }

    func startNewGame() {
        saves.delete(SaveStore.autosaveID)
        begin(restoreFrom: nil, visited: [], banner: nil)
    }

    @discardableResult
    func load(_ id: String, banner: String? = "RESTORING SAVED GAME...") -> Bool {
        let url = saves.fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let known = Set(saves.meta(for: id)?.visited ?? [])
        begin(restoreFrom: url, visited: known, banner: banner)
        return true
    }

    /// Save into a slot without ending the game (unlike the in-game SAVE).
    @discardableResult
    func save(to id: String) -> Bool {
        guard prompt != nil, !isOver else { return false }
        let room = CaveMap.shared.room(forLocation: location)?.label ?? "Somewhere"
        let meta = SaveMeta(date: Date(), room: room, score: score,
                            turns: turns, visited: visited.sorted())
        return saves.write(id: id, meta: meta)
    }

    func autosave() {
        save(to: SaveStore.autosaveID)
    }

    private func begin(restoreFrom url: URL?, visited known: Set<Int>, banner: String?) {
        advent_stop() // joins any running game thread first

        generation += 1
        let box = CallbackBox(generation: generation)
        callbackBox = box
        advent_set_callbacks(Unmanaged.passUnretained(box).toOpaque(),
                             engineOutput, enginePrompt, engineEnded)
        saves.directory.path.withCString { advent_set_save_directory($0) }

        lines = [""]
        revision &+= 1
        prompt = nil
        input = ""
        isOver = false
        askingFilename = false
        visited = known
        carried = []
        bearFollowing = false
        historyCursor = nil
        if let banner { append(banner + "\n") }

        let started: Bool
        if let url {
            started = url.path.withCString { advent_start($0) }
        } else {
            started = advent_start(nil)
        }
        if !started {
            append("\n*** THE CAVE FAILED TO OPEN. RESTART THE APP. ***\n")
        }
    }

    // MARK: Input

    func type(_ text: String) {
        guard !isOver else { return }
        if input.count < 200 { input += text }
        historyCursor = nil
    }

    func backspace() {
        if !input.isEmpty { input.removeLast() }
    }

    func clearInput() {
        input = ""
        historyCursor = nil
    }

    /// RETURN. After the game ends, RETURN starts a new one.
    func submit() {
        if isOver {
            startNewGame()
            return
        }
        guard prompt != nil else { return }
        let line = input
        input = ""
        historyCursor = nil
        if !line.trimmingCharacters(in: .whitespaces).isEmpty,
           history.last != line, !askingFilename {
            history.append(line)
            if history.count > 100 { history.removeFirst() }
        }
        prompt = nil
        line.withCString { advent_submit($0) }
    }

    /// Send a whole command at once (arrow keys).
    func send(_ command: String) {
        guard prompt != nil, !isOver else { return }
        input = command
        submit()
    }

    /// Cycle back through previous commands (TAB).
    func recallPrevious() {
        guard !history.isEmpty else { return }
        let next = (historyCursor ?? history.count) - 1
        let index = next < 0 ? history.count - 1 : next
        historyCursor = index
        input = history[index]
    }

    // MARK: Callbacks (main thread)

    fileprivate func receive(output text: String, generation gen: Int) {
        guard gen == generation else { return }
        append(text)
    }

    fileprivate func receive(prompt text: String, snapshot: EngineSnapshot, generation gen: Int) {
        guard gen == generation else { return }
        prompt = text
        askingFilename = snapshot.askingFilename
        location = snapshot.location
        isDark = snapshot.dark
        score = snapshot.score
        maxScore = snapshot.maxScore
        turns = snapshot.turns
        visited.formUnion(snapshot.seen)
        carried = snapshot.carried
        bearFollowing = snapshot.bearFollowing
    }

    fileprivate func receiveEnd(status: Int32, generation gen: Int) {
        guard gen == generation else { return }
        prompt = nil
        isOver = true
        saves.delete(SaveStore.autosaveID)
        append("\n*** PRESS RETURN TO PLAY AGAIN ***\n")
    }

    private func append(_ text: String) {
        var current = lines.removeLast()
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\n":
                lines.append(current)
                current = ""
            case "\r":
                continue
            default:
                current.unicodeScalars.append(scalar)
            }
        }
        lines.append(current)
        if lines.count > 1500 {
            lines.removeFirst(lines.count - 1200)
        }
        revision &+= 1
    }
}

// MARK: - C callbacks

/// Lives as long as one game; its address is the callback context.
final class CallbackBox: @unchecked Sendable {
    let generation: Int
    init(generation: Int) { self.generation = generation }
}

/// One thing in your inventory: the engine's object index (which picks its
/// sketch) and the game's wording for it.
struct CarriedItem: Sendable, Identifiable, Equatable {
    let id: Int
    let name: String
}

struct EngineSnapshot: Sendable {
    var location: Int
    var dark: Bool
    var askingFilename: Bool
    var score: Int
    var maxScore: Int
    var turns: Int
    var seen: [Int]
    var carried: [CarriedItem]
    var bearFollowing: Bool
}

private func generation(of ctx: UnsafeMutableRawPointer?) -> Int? {
    guard let ctx else { return nil }
    return Unmanaged<CallbackBox>.fromOpaque(ctx).takeUnretainedValue().generation
}

private func engineOutput(_ ctx: UnsafeMutableRawPointer?,
                          _ text: UnsafePointer<CChar>?,
                          _ length: Int) {
    guard let gen = generation(of: ctx), let text, length > 0 else { return }
    let string = String(decoding: UnsafeRawBufferPointer(start: text, count: length),
                        as: UTF8.self)
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            GameEngine.shared.receive(output: string, generation: gen)
        }
    }
}

private func enginePrompt(_ ctx: UnsafeMutableRawPointer?,
                          _ prompt: UnsafePointer<CChar>?,
                          _ snapshot: UnsafePointer<advent_snapshot_t>?) {
    guard let gen = generation(of: ctx), let snapshot else { return }
    let text = prompt.map { String(cString: $0) } ?? ""
    let s = snapshot.pointee
    let count = Int(s.location_count)
    var seen: [Int] = []
    withUnsafeBytes(of: s.seen) { raw in
        for i in 0..<min(count, raw.count) where raw[i] != 0 {
            seen.append(i)
        }
    }
    var carried: [CarriedItem] = []
    withUnsafeBytes(of: s.carried) { raw in
        let stride = MemoryLayout<Int32>.stride
        for i in 0..<min(Int(s.carried_count), raw.count / stride) {
            let obj = raw.load(fromByteOffset: i * stride, as: Int32.self)
            guard let name = advent_object_inventory(obj) else { continue }
            carried.append(CarriedItem(id: Int(obj), name: String(cString: name)))
        }
    }
    let snap = EngineSnapshot(location: Int(s.location), dark: s.dark,
                              askingFilename: s.asking_filename,
                              score: Int(s.score), maxScore: Int(s.max_score),
                              turns: Int(s.turns), seen: seen,
                              carried: carried, bearFollowing: s.bear_following)
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            GameEngine.shared.receive(prompt: text, snapshot: snap, generation: gen)
        }
    }
}

private func engineEnded(_ ctx: UnsafeMutableRawPointer?, _ status: Int32) {
    guard let gen = generation(of: ctx) else { return }
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            GameEngine.shared.receiveEnd(status: status, generation: gen)
        }
    }
}
