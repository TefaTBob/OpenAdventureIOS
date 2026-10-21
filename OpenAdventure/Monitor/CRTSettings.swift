import Observation
import SwiftUI

enum Phosphor: String, CaseIterable, Codable, Identifiable, Sendable {
    case green, amber, white, apple

    var id: String { rawValue }

    var name: String {
        switch self {
        case .green: "P1 Green"
        case .amber: "P3 Amber"
        case .white: "P4 White"
        case .apple: "Classic Green"
        }
    }

    var color: Color {
        switch self {
        case .green: Color(red: 0.25, green: 1.0, blue: 0.35)
        case .amber: Color(red: 1.0, green: 0.68, blue: 0.12)
        case .white: Color(red: 0.86, green: 0.92, blue: 1.0)
        case .apple: Color(red: 0.42, green: 1.0, blue: 0.5)
        }
    }
}

/// Everything the CRT shader can do. 0…1 sliders unless noted.
struct CRTSettings: Codable, Equatable, Sendable {
    var phosphor: Phosphor = .apple
    var brightness: Double = 0.55
    var contrast: Double = 0.55
    var bloom: Double = 0.55
    var curvature: Double = 0.35
    var staticNoise: Double = 0.12
    var jitter: Double = 0.08
    var flicker: Double = 0.15
    var horizontalSync: Double = 0.12
    var glowLine: Double = 0.35
    var scanlines: Double = 0.45
    var chromaShift: Double = 0.12
    var ambientGlow: Double = 0.3
    var columns: Int = 32           // text size: 32 large, 40 like the IIe, 80 small
    var uppercaseOnly: Bool = false // the ][+ couldn't show lowercase

    struct Preset: Identifiable {
        let name: String
        let settings: CRTSettings
        var id: String { name }
    }

    static let presets: [Preset] = [
        Preset(name: "Classic", settings: CRTSettings()),
        Preset(name: "Amber Terminal", settings: {
            var s = CRTSettings()
            s.phosphor = .amber; s.bloom = 0.65; s.scanlines = 0.3; s.glowLine = 0.2
            s.horizontalSync = 0.05; s.curvature = 0.25
            return s
        }()),
        Preset(name: "Green Scanlines", settings: {
            var s = CRTSettings()
            s.phosphor = .green; s.scanlines = 0.85; s.bloom = 0.45; s.curvature = 0.4
            s.staticNoise = 0.08
            return s
        }()),
        Preset(name: "Paper White", settings: {
            var s = CRTSettings()
            s.phosphor = .white; s.bloom = 0.35; s.scanlines = 0.25; s.curvature = 0.2
            s.staticNoise = 0.05; s.flicker = 0.05; s.glowLine = 0.1; s.chromaShift = 0.3
            return s
        }()),
        Preset(name: "Worn Out", settings: {
            var s = CRTSettings()
            s.phosphor = .green; s.bloom = 0.8; s.curvature = 0.6; s.staticNoise = 0.45
            s.jitter = 0.4; s.flicker = 0.5; s.horizontalSync = 0.55; s.glowLine = 0.6
            s.chromaShift = 0.5; s.scanlines = 0.6
            return s
        }()),
        Preset(name: "Crisp (no effects)", settings: {
            var s = CRTSettings()
            s.bloom = 0.15; s.curvature = 0; s.staticNoise = 0; s.jitter = 0; s.flicker = 0
            s.horizontalSync = 0; s.glowLine = 0; s.scanlines = 0; s.chromaShift = 0
            s.ambientGlow = 0.1
            return s
        }()),
    ]

    /// Keep text, columns and case when switching looks.
    func applying(_ preset: CRTSettings) -> CRTSettings {
        var s = preset
        s.columns = columns
        s.uppercaseOnly = uppercaseOnly
        return s
    }
}

/// App-wide preferences, persisted to UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var crt: CRTSettings { didSet { persist() } }
    var keyClicks: Bool { didSet { persist() } }
    var haptics: Bool { didSet { persist() } }
    var showUnexploredExits: Bool { didSet { persist() } }

    private struct Stored: Codable {
        var crt: CRTSettings
        var keyClicks: Bool
        var haptics: Bool
        var showUnexploredExits: Bool
    }

    private static let key = "settings.v2"
    private static let oldKey = "settings.v1"

    private init() {
        let defaults = UserDefaults.standard
        var stored: Stored?
        if let data = defaults.data(forKey: Self.key) {
            stored = try? JSONDecoder().decode(Stored.self, from: data)
        } else if let data = defaults.data(forKey: Self.oldKey),
                  var old = try? JSONDecoder().decode(Stored.self, from: data) {
            // Settings from before text sizes: keep everything, but move the
            // old 40-column default up to the new Large text.
            if old.crt.columns == 40 { old.crt.columns = 32 }
            stored = old
        }
        if let stored {
            crt = stored.crt
            keyClicks = stored.keyClicks
            haptics = stored.haptics
            showUnexploredExits = stored.showUnexploredExits
        } else {
            crt = CRTSettings()
            keyClicks = true
            haptics = true
            showUnexploredExits = true
        }
    }

    private func persist() {
        let stored = Stored(crt: crt, keyClicks: keyClicks, haptics: haptics,
                            showUnexploredExits: showUnexploredExits)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
