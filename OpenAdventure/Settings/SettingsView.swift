import SwiftUI

/// Opened by the gear key. Game (save/load/new), Screen (CRT controls),
/// Controls, and About. Shown as a half-height sheet first so the monitor
/// stays visible while you tune the picture.
struct SettingsView: View {
    @Environment(GameEngine.self) private var engine
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var confirm: Confirmation?
    @State private var toast: String?
    @State private var refresh = 0

    enum Confirmation: Identifiable {
        case save(String), load(String), newGame, delete(String)
        var id: String {
            switch self {
            case .save(let s): "save-" + s
            case .load(let s): "load-" + s
            case .newGame: "new"
            case .delete(let s): "delete-" + s
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                gameSection
                slotsSection
                typedSavesSection
                screenSection
                controlsSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(item: $confirm) { item in alert(for: item) }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: Game

    private var gameSection: some View {
        Section {
            LabeledContent("Score", value: "\(engine.score) of \(engine.maxScore)")
            LabeledContent("Turns", value: "\(engine.turns)")
            LabeledContent("Location",
                           value: CaveMap.shared.room(forLocation: engine.location)?.label ?? "—")
            Button("New Game", role: .destructive) { confirm = .newGame }
        } header: {
            Text("Game")
        } footer: {
            Text("Saves here don't end the game or cost points. The in-game SAVE command still works the original way: it costs points and quits.")
        }
    }

    private var slotsSection: some View {
        Section("Save Slots") {
            slotRow(id: SaveStore.autosaveID, title: "Autosave", canSave: false)
            ForEach(Array(SaveStore.slotIDs.enumerated()), id: \.element) { index, id in
                slotRow(id: id, title: "Slot \(index + 1)", canSave: true)
            }
        }
        .id(refresh)
    }

    private func slotRow(id: String, title: String, canSave: Bool) -> some View {
        let exists = engine.saves.exists(id)
        let meta = engine.saves.meta(for: id)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                if exists, let meta {
                    Text("\(meta.room) · \(meta.score) pts · \(meta.turns) turns")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(meta.date, format: .dateTime.month().day().hour().minute())
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text(exists ? "Saved game" : "Empty")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if canSave {
                Button("Save") {
                    if exists { confirm = .save(id) } else { doSave(id) }
                }
                .buttonStyle(.bordered)
                .disabled(engine.isOver || engine.prompt == nil)
            }
            Button("Load") { confirm = .load(id) }
                .buttonStyle(.borderedProminent)
                .disabled(!exists)
        }
    }

    @ViewBuilder private var typedSavesSection: some View {
        let typed = engine.saves.typedSaves()
        if !typed.isEmpty {
            Section {
                ForEach(typed, id: \.self) { name in
                    HStack {
                        Text(name).font(.body.monospaced())
                        Spacer()
                        Button("Load") { confirm = .load(name) }
                            .buttonStyle(.bordered)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { confirm = .delete(name) }
                    }
                }
            } header: {
                Text("Saved with the SAVE command")
            }
            .id(refresh)
        }
    }

    private func alert(for item: Confirmation) -> Alert {
        switch item {
        case .save(let id):
            return Alert(title: Text("Overwrite this slot?"),
                         primaryButton: .destructive(Text("Save")) { doSave(id) },
                         secondaryButton: .cancel())
        case .load(let id):
            return Alert(title: Text("Load this game?"),
                         message: Text("Unsaved progress in the current game will be lost."),
                         primaryButton: .destructive(Text("Load")) {
                             engine.load(id)
                             dismiss()
                         },
                         secondaryButton: .cancel())
        case .newGame:
            return Alert(title: Text("Start a new game?"),
                         message: Text("Unsaved progress will be lost."),
                         primaryButton: .destructive(Text("New Game")) {
                             engine.startNewGame()
                             dismiss()
                         },
                         secondaryButton: .cancel())
        case .delete(let id):
            return Alert(title: Text("Delete “\(id)”?"),
                         primaryButton: .destructive(Text("Delete")) {
                             engine.saves.delete(id)
                             refresh += 1
                         },
                         secondaryButton: .cancel())
        }
    }

    private func doSave(_ id: String) {
        let ok = engine.save(to: id)
        refresh += 1
        show(ok ? "Saved" : "Couldn't save right now")
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { toast = nil }
        }
    }

    // MARK: Screen

    private var screenSection: some View {
        @Bindable var settings = settings
        return Section {
            Picker("Look", selection: presetBinding) {
                Text("Custom").tag("Custom")
                ForEach(CRTSettings.presets) { preset in
                    Text(preset.name).tag(preset.name)
                }
            }
            Picker("Phosphor", selection: $settings.crt.phosphor) {
                ForEach(Phosphor.allCases) { p in
                    Text(p.name).tag(p)
                }
            }
            Picker("Text size", selection: $settings.crt.columns) {
                Text("Large").tag(32)
                Text("Medium").tag(40)
                Text("Small").tag(80)
            }
            .pickerStyle(.segmented)
            Toggle("Uppercase only", isOn: $settings.crt.uppercaseOnly)

            slider("Brightness", $settings.crt.brightness)
            slider("Contrast", $settings.crt.contrast)
            slider("Bloom", $settings.crt.bloom)
            slider("Curvature", $settings.crt.curvature)
            slider("Scanlines", $settings.crt.scanlines)
            slider("Static noise", $settings.crt.staticNoise)
            slider("Jitter", $settings.crt.jitter)
            slider("Flicker", $settings.crt.flicker)
            slider("Horizontal sync", $settings.crt.horizontalSync)
            slider("Glow line", $settings.crt.glowLine)
            slider("Color fringing", $settings.crt.chromaShift)
            slider("Ambient glow", $settings.crt.ambientGlow)
        } header: {
            Text("Screen")
        } footer: {
            Text("With Reduce Motion on, jitter, flicker, sync wobble and the glow line are paused.")
        }
    }

    private var presetBinding: Binding<String> {
        Binding(
            get: {
                CRTSettings.presets.first {
                    settings.crt.applying($0.settings) == settings.crt
                }?.name ?? "Custom"
            },
            set: { name in
                if let preset = CRTSettings.presets.first(where: { $0.name == name }) {
                    settings.crt = settings.crt.applying(preset.settings)
                }
            }
        )
    }

    private func slider(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1)
        }
    }

    // MARK: Controls

    private var controlsSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle("Key clicks", isOn: $settings.keyClicks)
            Toggle("Haptics", isOn: $settings.haptics)
            Toggle("Show unexplored exits on map", isOn: $settings.showUnexploredExits)
            DisclosureGroup("Keyboard guide") {
                guideRow("arrow.counterclockwise", "↺ key", "Bring back your previous command (tap again to go further back)")
                guideRow("map", "Map key", "Open the map")
                guideRow("note.text", "Notes key", "Open the notepad")
                guideRow("hand.draw", "Swipe the screen", "Right for the map, left for notes")
                guideRow("arrow.up.and.down", "Drag the screen", "Scroll back through earlier text")
                guideRow("keyboard", "Hardware keyboard", "Arrow keys walk N/S/E/W; Tab recalls; Esc clears")
            }
        } header: {
            Text("Controls")
        }
    }

    private func guideRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        Label {
            VStack(alignment: .leading) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section("About") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Colossal Cave Adventure")
                    .font(.headline)
                Text("By Will Crowther (1976) and Don Woods (1977–1995). Open Adventure 1.22, the forward port of Adventure 2.5 maintained by Eric S. Raymond, runs unmodified inside this app.")
                    .font(.footnote)
            }
            .padding(.vertical, 4)
            NavigationLink("License") {
                ScrollView {
                    Text(Self.licenseText)
                        .font(.footnote.monospaced())
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle("License")
            }
        }
    }

    static let licenseText: String = {
        let header = """
        Open Adventure
        Copyright (C) 1977, 2005 by Will Crowther and Don Woods
        Copyright (C) Eric S. Raymond


        """
        if let url = Bundle.main.url(forResource: "OpenAdventure-LICENSE", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return header + text
        }
        return header + "BSD 2-Clause License"
    }()
}
