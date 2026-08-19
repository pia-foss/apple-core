#if canImport(UIKit) && !os(watchOS)

    import Combine
    import CoreArchitecture
    import SwiftUI
    import UIKit

    extension Spaceship {

        /// Results the launch flow reports to whoever started it.
        public enum Output {
            case flightFinished(ship: Ship, phase: Phase)
        }

        /// The UIKit counterpart to `SpaceshipFlow`: the same two screens, pushed onto a navigation
        /// controller instead of driven by a `NavigationStack` path.
        ///
        /// Worth reading beside `Flow` rather than instead of it. `Flow` keeps the path and each ship's
        /// last result in a store, where both are reducer-tested; this holds the same facts in plain
        /// properties, which is what an imperative stack costs — see `refreshFleet()` for the bill.
        @MainActor
        public final class Coordinator: FlowCoordinator {

            private let navigationController: UINavigationController
            private let track: @MainActor (String) -> Void
            private nonisolated let subject = PassthroughSubject<Output, Never>()

            /// Fires once per finished flight, whether it reached orbit or failed its checks.
            public nonisolated var output: AnyPublisher<Output, Never> { subject.eraseToAnyPublisher() }

            /// What each ship's last launch came to.
            ///
            /// `Flow` holds this in reducer state. Here it is a property, because there is no store to put
            /// it in — so every read below is the coordinator answering what the fleet screen used to ask
            /// its own state.
            private var results: [Ship.ID: Phase] = [:]

            /// The hosted fleet screen, kept so a finished flight can push fresh results back into it.
            private weak var fleetHost: UIHostingController<FleetScreen>?

            /// - Parameters:
            ///   - navigationController: The stack this flow pushes onto.
            ///   - track: Receives a line of telemetry.
            public init(
                navigationController: UINavigationController,
                track: @escaping @MainActor (String) -> Void
            ) {
                self.navigationController = navigationController
                self.track = track
            }

            /// Puts the fleet screen on the stack, unanimated because it is the flow's first screen.
            ///
            /// `nonisolated`, with the work hopped onto the main actor, because `FlowCoordinator` is not
            /// itself `@MainActor` — an isolated witness to a non-isolated requirement is an error in the
            /// Swift 6 language mode.
            public nonisolated func start() {
                Task { @MainActor in
                    let host = UIHostingController(rootView: makeFleetScreen())
                    host.title = "Fleet"
                    fleetHost = host
                    navigationController.pushViewController(host, animated: false)
                }
            }

            private func makeFleetScreen() -> FleetScreen {
                FleetScreen(
                    dependencies: .live,
                    results: results,
                    onSelect: { [weak self] ship in self?.showLaunch(for: ship) }
                )
            }

            /// Pushes the launch screen for `ship`, seeded with whatever its last flight came to.
            ///
            /// Both handoffs happen here: the recorded result goes down into the launch state, and
            /// `reportResult` brings the final phase back up. Neither screen learns the other exists.
            private func showLaunch(for ship: Ship) {
                let screen = LaunchScreen(
                    state: Launch.State(ship: ship, phase: results[ship.id] ?? .grounded),
                    dependencies: .live(
                        track: track,
                        reportResult: { [weak self] phase in self?.record(phase, for: ship) }
                    )
                )
                let host = UIHostingController(rootView: screen)
                host.title = ship.name
                navigationController.pushViewController(host, animated: true)
            }

            private func record(_ phase: Phase, for ship: Ship) {
                results[ship.id] = phase
                refreshFleet()
                subject.send(.flightFinished(ship: ship, phase: phase))
            }

            /// Rebuilds the fleet screen so it renders the result that just came in.
            ///
            /// The screen was handed a snapshot of `results`, so without this a ship that reached orbit
            /// still reads as grounded on the way back. `SpaceshipFlow` needs no equivalent: its list
            /// re-renders from the store. Replacing `rootView` keeps the screen's own `@StateObject`.
            private func refreshFleet() {
                fleetHost?.rootView = makeFleetScreen()
            }
        }
    }

#endif
