import SwiftUI

/// The master screen: pick a ship to launch.
///
/// Two actions, and no state of its own. It takes a slice of state plus `send`, so it has never heard of
/// `Store` and previews from a literal.
struct FleetView: View {

    let fleet: [Spaceship.Ship]
    let isLoading: Bool
    let flights: [Spaceship.Ship.ID: Spaceship.Flight]
    let send: (Spaceship.Action) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    ForEach(fleet) { ship in
                        Button {
                            send(.shipSelected(ship))
                        } label: {
                            // The same `Flight` the launch screen renders, so the two cannot disagree.
                            ShipRow(ship: ship, phase: flights[ship.id]?.phase)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
        .spaceBackground()
        .onAppear { send(.fleetAppeared) }
    }
}

/// One ship, showing whatever its flight has come to.
private struct ShipRow: View {

    let ship: Spaceship.Ship
    let phase: Spaceship.Flight.Phase?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: phase?.symbolName ?? "location.north.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(phase?.tint ?? .white.opacity(0.8))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(ship.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(subtitleTint)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.35))
        }
        .demoCard(padding: 14)
    }
}

extension ShipRow {

    /// What the flight has come to, or the ship's readiness when it has nothing to report.
    ///
    /// A flight wins because it is the newer fact: a ship in orbit is more usefully described by that than
    /// by having been flightworthy before it left.
    fileprivate var subtitle: String {
        if let label = phase?.fleetLabel {
            return label
        }
        return ship.readiness == .ready ? "Ready" : "In maintenance"
    }

    /// The phase's colour when it has something to report, otherwise a muted default.
    fileprivate var subtitleTint: Color {
        guard let phase, phase.fleetLabel != nil else { return .white.opacity(0.5) }
        return phase.tint
    }
}

#if DEBUG

    struct FleetView_Previews: PreviewProvider {
        static var previews: some View {
            let fleet = Spaceship.Ship.demoFleet
            return FleetView(
                fleet: fleet,
                isLoading: false,
                flights: [
                    fleet[0].id: Spaceship.Flight(ship: fleet[0], phase: .inOrbit, altitude: 100),
                    fleet[2].id: Spaceship.Flight(
                        ship: fleet[2],
                        phase: .checksFailed(reason: "Ship in maintenance")
                    )
                ],
                send: { _ in }
            )
            .preferredColorScheme(.dark)
        }
    }

#endif
