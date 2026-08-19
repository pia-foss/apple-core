import CoreArchitecture
import SwiftUI

/// The detail screen: launch one ship, or abort.
///
/// It owns its own store, so nothing hands it a `send` closure — it dispatches to its own reducer. What it
/// does take is `onFinish`, an *output* closure: the screen reports a result upward and does not decide
/// what anyone does with it. That is the output-closure direction of travel, inverted from `send`.
struct LaunchScreen: View {

    @StateObject private var store: Store<Launch.State, Launch.Action>

    /// Creates the screen and the store behind it.
    ///
    /// - Parameters:
    ///   - state: The launch to start from, seeded by the flow with the fleet's last recorded result.
    ///   - dependencies: The collaborators the reducer runs through.
    init(state: Launch.State, dependencies: Launch.Dependencies) {
        _store = StateObject(
            wrappedValue: Store(
                initial: state,
                reduce: Launch.Reducer(dependencies: dependencies).reduce
            )
        )
    }

    var body: some View {
        VStack(spacing: 24) {
            PhaseBadgeView(phase: store.state.phase)
                .frame(height: 150)

            Text(store.state.phase.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            AltitudeBarView(altitude: store.state.altitude, tint: store.state.phase.tint)

            controls

            Spacer()
        }
        .padding(20)
        .spaceBackground()
    }

    /// The two controls, styled by what they do rather than by the current phase.
    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                store.send(.launchTapped)
            } label: {
                Text(store.state.phase == .grounded ? "Launch" : "Launch again")
            }
            .buttonStyle(.launch)
            .disabled(store.state.phase.isInFlight)

            Button {
                store.send(.abortTapped)
            } label: {
                Text("Abort")
            }
            .buttonStyle(.abort)
            .disabled(!store.state.phase.isInFlight)
        }
    }
}

/// The phase, as one large glyph — or as the remaining seconds during a countdown.
private struct PhaseBadgeView: View {

    let phase: Spaceship.Phase

    var body: some View {
        ZStack {
            Circle()
                .fill(phase.tint.opacity(0.15))
                .frame(width: 132, height: 132)

            if case .countdown(let seconds) = phase {
                Text("\(seconds)")
                    .font(.system(size: 68, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(phase.tint)
            } else {
                Image(systemName: phase.symbolName)
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(phase.tint)
            }
        }
    }
}

/// Altitude as a bar rather than a moving glyph, so nothing jumps as the number changes.
private struct AltitudeBarView: View {

    let altitude: Int
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(altitude), total: 100)
                .tint(tint)

            HStack {
                Text("Altitude")
                Spacer()
                Text("\(altitude) km")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.55))
        }
    }
}

#if DEBUG

    struct LaunchScreen_Previews: PreviewProvider {
        static var previews: some View {
            ForEach(
                [
                    Spaceship.Phase.grounded,
                    .countdown(secondsRemaining: 2),
                    .ascending,
                    .inOrbit
                ],
                id: \.title
            ) { phase in
                LaunchScreen(
                    state: Launch.State(
                        ship: Spaceship.Ship.demoFleet[0],
                        phase: phase,
                        altitude: phase == .inOrbit ? 100 : 0
                    ),
                    dependencies: .immediate()
                )
                .preferredColorScheme(.dark)
            }
        }
    }

#endif
