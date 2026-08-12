import SwiftUI

/// The detail screen: launch one ship, or abort.
///
/// Two actions now that the navigation stack owns going back — the screen never dismisses itself. Every
/// control's enabled state is a function of `flight.phase` alone, which is the practical payoff of
/// modelling the phase as one enum.
struct LaunchView: View {

    let flight: Spaceship.Flight
    let send: (Spaceship.Action) -> Void

    var body: some View {
        VStack(spacing: 24) {
            // A fixed frame, so changing phase swaps the badge without shifting anything below it.
            PhaseBadge(phase: flight.phase)
                .frame(height: 150)

            Text(flight.phase.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            AltitudeBar(altitude: flight.altitude, tint: flight.phase.tint)

            controls

            Spacer()
        }
        .padding(20)
        .spaceBackground()
    }

    /// The two controls, styled by what they do rather than by the current phase.
    ///
    /// Tinting a button by phase conflated "which state am I in" with "what will this do", and rendered
    /// white on white whenever the phase's tint was light.
    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                send(.launchTapped)
            } label: {
                Text(flight.phase == .grounded ? "Launch" : "Launch again")
            }
            .buttonStyle(.launch)
            .disabled(flight.phase.isInFlight)

            Button {
                send(.abortTapped)
            } label: {
                Text("Abort")
            }
            .buttonStyle(.abort)
            .disabled(!flight.phase.isInFlight)
        }
    }
}

/// The phase, as one large glyph — or as the remaining seconds during a countdown.
private struct PhaseBadge: View {

    let phase: Spaceship.Flight.Phase

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
private struct AltitudeBar: View {

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

    struct LaunchView_Previews: PreviewProvider {
        static var previews: some View {
            ForEach(
                [
                    Spaceship.Flight(ship: Spaceship.Ship.demoFleet[0]),
                    Spaceship.Flight(
                        ship: Spaceship.Ship.demoFleet[0],
                        phase: .countdown(secondsRemaining: 2)
                    ),
                    Spaceship.Flight(
                        ship: Spaceship.Ship.demoFleet[0],
                        phase: .ascending,
                        altitude: 60
                    ),
                    Spaceship.Flight(ship: Spaceship.Ship.demoFleet[0], phase: .inOrbit, altitude: 100)
                ],
                id: \.phase.title
            ) { flight in
                LaunchView(flight: flight, send: { _ in })
                    .preferredColorScheme(.dark)
            }
        }
    }

#endif
