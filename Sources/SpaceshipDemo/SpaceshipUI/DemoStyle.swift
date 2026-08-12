import SwiftUI

extension View {

    /// Puts the demo's gradient behind the view.
    ///
    /// Applied per screen rather than once at the root, because each navigation destination draws its own
    /// background.
    func spaceBackground() -> some View {
        background {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.16),
                    Color(red: 0.16, green: 0.10, blue: 0.33)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    /// Wraps the view in the demo's translucent card.
    func demoCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A filled pill whose fill and text colours are both set explicitly.
///
/// `.borderedProminent` derives its label colour from the tint, so a light tint renders white on white,
/// and its disabled treatment dims to near-invisible against a dark background. Stating both colours here
/// keeps contrast a property of the style rather than of whatever tint a caller happens to pass.
struct DemoButtonStyle: ButtonStyle {

    let fill: Color
    let text: Color

    func makeBody(configuration: Configuration) -> some View {
        // A nested view, because `@Environment` is only reliably tracked inside a `View` body — a
        // `ButtonStyle` is not one, so reading `isEnabled` on the style itself would go stale. It cannot
        // be called `Body`: that name would be taken as the protocol's associated type.
        StyledLabel(configuration: configuration, fill: fill, text: text)
    }

    private struct StyledLabel: View {

        let configuration: Configuration
        let fill: Color
        let text: Color

        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isEnabled ? text : .white.opacity(0.3))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(isEnabled ? fill : Color.white.opacity(0.08))
                .clipShape(Capsule())
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}

// The `where Self ==` shape is what makes `.buttonStyle(.launch)` resolve, and is how SwiftUI defines
// `.bordered` and `.borderedProminent`.

extension ButtonStyle where Self == DemoButtonStyle {

    /// The primary action on a screen.
    static var launch: Self { Self(fill: .orange, text: .black.opacity(0.9)) }

    /// A destructive or interrupting action.
    static var abort: Self { Self(fill: Color.red.opacity(0.9), text: .white) }
}

// Presentation values for the feature's enums.
//
// They live in the view layer on purpose: the state layer imports only Foundation, and giving it a
// `Color` would couple the state machine to SwiftUI for no gain.

extension Spaceship.Flight.Phase {

    /// The SF Symbol standing for this phase.
    var symbolName: String {
        switch self {
        case .grounded: return "location.north.fill"
        case .runningChecks: return "gearshape.fill"
        case .countdown: return "timer"
        case .ascending: return "flame.fill"
        case .inOrbit: return "globe.americas.fill"
        case .checksFailed: return "wrench.and.screwdriver.fill"
        }
    }

    /// The accent colour for this phase.
    var tint: Color {
        switch self {
        case .grounded: return .white
        case .runningChecks: return .cyan
        case .countdown, .ascending: return .orange
        case .inOrbit: return .green
        case .checksFailed: return .yellow
        }
    }
}
