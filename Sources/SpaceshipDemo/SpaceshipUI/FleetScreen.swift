import CoreArchitecture
import SwiftUI

/// The master screen: pick a ship to launch.
///
/// Owns its own store, like every screen here. It reports a selection through `onSelect` and has no idea
/// that doing so pushes anything — deciding what a selection means is the flow's job.
struct FleetScreen: View {

    @StateObject private var store: Store<Fleet.State, Fleet.Action>

    /// What each ship's last launch came to, owned by the flow and passed down to render.
    ///
    /// Not this feature's state: `Launch` produces it and the flow records it. The screen only draws it.
    private let results: [Spaceship.Ship.ID: Spaceship.Phase]

    /// Called when the pilot picks a ship.
    private let onSelect: (Spaceship.Ship) -> Void

    /// Creates the screen and the store behind it.
    ///
    /// - Parameters:
    ///   - dependencies: The collaborators the reducer runs through.
    ///   - results: What each ship's last launch came to.
    ///   - onSelect: Called when the pilot picks a ship.
    init(
        dependencies: Fleet.Dependencies,
        results: [Spaceship.Ship.ID: Spaceship.Phase],
        onSelect: @escaping (Spaceship.Ship) -> Void
    ) {
        _store = StateObject(
            wrappedValue: Store(
                initial: Fleet.State(),
                reduce: Fleet.Reducer(dependencies: dependencies).reduce
            )
        )
        self.results = results
        self.onSelect = onSelect
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if store.state.isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    ForEach(store.state.ships) { ship in
                        Button {
                            onSelect(ship)
                        } label: {
                            ShipRowView(ship: ship, phase: results[ship.id])
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
        .spaceBackground()
        .onAppear { store.send(.appeared) }
    }
}

/// One ship, showing whatever its last launch came to.
private struct ShipRowView: View {

    let ship: Spaceship.Ship
    let phase: Spaceship.Phase?

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

extension ShipRowView {

    /// What the last launch came to, or the ship's readiness when there is nothing to report.
    ///
    /// A result wins because it is the newer fact: a ship in orbit is more usefully described by that than by
    /// having been flightworthy before it left.
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

    struct FleetScreen_Previews: PreviewProvider {
        static var previews: some View {
            let ships = Spaceship.Ship.demoFleet
            return FleetScreen(
                dependencies: .immediate(ships: ships),
                results: [
                    ships[0].id: .inOrbit,
                    ships[2].id: .checksFailed(reason: "Ship in maintenance")
                ],
                onSelect: { _ in }
            )
            .preferredColorScheme(.dark)
        }
    }

#endif
