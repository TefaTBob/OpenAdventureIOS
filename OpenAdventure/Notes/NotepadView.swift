import SwiftUI

/// A yellow legal pad beside the computer, for the notes every adventurer
/// keeps. Saved to Documents/Notes.txt (visible in the Files app).
struct NotepadView: View {
    var onClose: () -> Void

    @Environment(GameEngine.self) private var engine
    @State private var text = NotesStore.load()
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var editing: Bool

    private let paper = Color(red: 0.99, green: 0.95, blue: 0.66)
    private let margin = Color(red: 0.86, green: 0.36, blue: 0.36)
    private let ink = Color(red: 0.12, green: 0.16, blue: 0.38)

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .topLeading) {
                paper
                // Red double margin, like a legal pad
                HStack(spacing: 3) {
                    Rectangle().fill(margin.opacity(0.7)).frame(width: 1)
                    Rectangle().fill(margin.opacity(0.7)).frame(width: 1)
                }
                .padding(.leading, 34)
                .allowsHitTesting(false)

                TextEditor(text: $text)
                    .focused($editing)
                    .scrollContentBackground(.hidden)
                    .font(.custom("Noteworthy-Light", size: 19, relativeTo: .body))
                    .foregroundStyle(ink)
                    .tint(ink)
                    .padding(.leading, 40)
                    .padding(.trailing, 12)
                    .autocorrectionDisabled(false)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Notes, hunches, the words you heard\non the wind…")
                                .font(.custom("Noteworthy-Light", size: 19, relativeTo: .body))
                                .foregroundStyle(ink.opacity(0.35))
                                .padding(.leading, 45)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .background(paper)
        .onChange(of: text) { scheduleSave() }
        .onDisappear { NotesStore.save(text) }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: { editing = false; onClose() }) {
                Label("Game", systemImage: "chevron.left")
            }
            Spacer()
            Text("NOTES")
                .font(.custom("Noteworthy-Bold", size: 20, relativeTo: .headline))
            Spacer()
            Button {
                insertRoom()
            } label: {
                Label("Room", systemImage: "plus")
            }
            .accessibilityLabel("Insert current room name")
            if editing {
                Button("Done") { editing = false }
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            // Glued binding strip at the top of the pad
            Color(red: 0.55, green: 0.15, blue: 0.13).opacity(0.85)
                .overlay(Color.white.opacity(0.75))
        )
    }

    private func insertRoom() {
        let name = CaveMap.shared.room(forLocation: engine.location)?.label ?? "Somewhere dark"
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += "— \(name): "
        editing = true
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = text
        saveTask = Task {
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            NotesStore.save(snapshot)
        }
    }
}

enum NotesStore {
    static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notes.txt")
    }

    static func load() -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    static func save(_ text: String) {
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
