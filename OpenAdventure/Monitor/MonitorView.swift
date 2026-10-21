import SwiftUI

/// Retro colors shared by the monitor and keyboard.
enum Retro {
    /// The beige plastic of an early-80s home computer.
    static let caseTop = Color(red: 0.86, green: 0.81, blue: 0.69)
    static let caseBottom = Color(red: 0.76, green: 0.70, blue: 0.57)
    static let caseShadow = Color(red: 0.55, green: 0.49, blue: 0.38)
    static let screenSurround = Color(red: 0.10, green: 0.09, blue: 0.085)
    /// Dark taupe key caps with cream legends.
    static let keyTop = Color(red: 0.36, green: 0.32, blue: 0.29)
    static let keyFace = Color(red: 0.29, green: 0.26, blue: 0.235)
    static let keySkirt = Color(red: 0.17, green: 0.15, blue: 0.13)
    static let legend = Color(red: 0.93, green: 0.90, blue: 0.82)
}

/// A beige monitor casing around a picture tube, with the name badge and
/// power lamp below the screen. `screen` is drawn inside the tube with
/// rounded, curved-looking glass and a faint reflection on top.
/// With `aspect` nil (the default) the tube fills all the space it's given.
struct MonitorView<Screen: View>: View {
    var aspect: CGFloat? = nil
    var powerOn = true
    @ViewBuilder var screen: Screen

    var body: some View {
        ZStack {
            // Casing
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Retro.caseTop, Retro.caseBottom],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                        .blendMode(.overlay)
                )
                .shadow(color: .black.opacity(0.35), radius: 5, y: 3)

            VStack(spacing: 4) {
                // Recessed screen surround
                // The opening in the case is generously rounded, like the
                // Apple IIe monitor's molded bezel.
                ZStack {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(Retro.screenSurround)
                        .overlay(
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .stroke(LinearGradient(colors: [.black.opacity(0.8), .white.opacity(0.3)],
                                                       startPoint: .top, endPoint: .bottom),
                                        lineWidth: 3)
                        )
                    tube.padding(7)
                }

                // Badge strip with power lamp
                HStack(spacing: 8) {
                    Text("COLOSSAL CAVE")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Retro.caseShadow)
                    Spacer()
                    Circle()
                        .fill(powerOn ? Color(red: 0.3, green: 1, blue: 0.4) : .gray)
                        .frame(width: 5, height: 5)
                        .shadow(color: powerOn ? .green : .clear, radius: 3)
                }
                .padding(.horizontal, 6)
            }
            .padding(EdgeInsets(top: 9, leading: 9, bottom: 5, trailing: 9))
        }
    }

    @ViewBuilder private var tube: some View {
        // Generous corner rounding sells the curved glass of the tube.
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        let content = screen
            .clipShape(shape)
            .overlay(
                // Glass reflection, not part of the picture
                shape.fill(LinearGradient(colors: [.white.opacity(0.09), .clear, .clear,
                                                   .white.opacity(0.03)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .allowsHitTesting(false)
            )
            .overlay(shape.stroke(.black.opacity(0.9), lineWidth: 2).allowsHitTesting(false))
        if let aspect {
            content.aspectRatio(aspect, contentMode: .fit)
        } else {
            content
        }
    }
}
