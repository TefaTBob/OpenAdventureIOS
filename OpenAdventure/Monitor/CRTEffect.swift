import SwiftUI

/// Applies the CRT shader (CRT.metal) to grayscale content, animated.
struct CRTEffect: ViewModifier {
    var settings: CRTSettings
    /// Pixel rows in the source picture, so scanlines line up with pixels.
    var sourceRows: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let epoch = Date()

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
            let time = Float(context.date.timeIntervalSince(Self.epoch)
                .truncatingRemainder(dividingBy: 3600))
            let s = motionAdjusted(settings)
            let rows = Float(sourceRows)
            content.visualEffect { view, proxy in
                view.layerEffect(
                    ShaderLibrary.crtMonitor(
                        .float2(proxy.size),
                        .float(time),
                        .color(s.phosphor.color),
                        .float(Float(s.brightness)),
                        .float(Float(s.contrast)),
                        .float(Float(s.bloom)),
                        .float(Float(s.curvature)),
                        .float(Float(s.staticNoise)),
                        .float(Float(s.jitter)),
                        .float(Float(s.flicker)),
                        .float(Float(s.horizontalSync)),
                        .float(Float(s.glowLine)),
                        .float(Float(s.scanlines)),
                        .float(Float(s.chromaShift)),
                        .float(rows),
                        .float(Float(s.ambientGlow))
                    ),
                    maxSampleOffset: CGSize(width: 12, height: 12)
                )
            }
        }
    }

    /// With Reduce Motion on, keep the look but drop anything that moves.
    private func motionAdjusted(_ s: CRTSettings) -> CRTSettings {
        guard reduceMotion else { return s }
        var c = s
        c.jitter = 0
        c.flicker = 0
        c.horizontalSync = 0
        c.glowLine = 0
        c.staticNoise = min(c.staticNoise, 0.05)
        return c
    }
}

extension View {
    func crt(_ settings: CRTSettings, sourceRows: Double) -> some View {
        modifier(CRTEffect(settings: settings, sourceRows: sourceRows))
    }
}
