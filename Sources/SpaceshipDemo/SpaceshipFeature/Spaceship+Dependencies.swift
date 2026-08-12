import Foundation

extension Spaceship {

    /// The collaborators that keep `Spaceship.Reducer` pure.
    ///
    /// Mixed on purpose, following ADR 0010's composition rule: protocols for collaborators that own a
    /// decision and get shared, typed closures for one-off operations. Nothing here holds logic — the
    /// protocols point at named types, and the wiring below only assembles them.
    public struct Dependencies {

        /// Where the fleet comes from.
        ///
        /// Named for what it is rather than what it holds: `state.fleet` is an array of ships, and a
        /// collaborator sharing that name would read like one at every call site.
        public var fleetRepository: any FleetRepository

        /// The rules deciding whether a ship may fly.
        public var launchService: any LaunchService

        /// Suspends for a number of seconds.
        ///
        /// A closure rather than a protocol: one operation, no decision of its own. Time is injected for
        /// the same reason the network is — a test that waited three real seconds for a countdown would
        /// be three seconds slower and no more correct.
        public var wait: (TimeInterval) async -> Void

        /// Sends a line of telemetry to ground control.
        ///
        /// Main-actor isolated so an effect body can call it without `await`. A closure keeps this layer
        /// from knowing what renders the result.
        public var track: @MainActor (String) -> Void

        /// Creates a dependency set from its four collaborators.
        ///
        /// - Parameters:
        ///   - fleetRepository: Where the fleet comes from.
        ///   - launchService: The rules deciding whether a ship may fly.
        ///   - wait: Suspends for a number of seconds.
        ///   - track: Receives a line of telemetry.
        public init(
            fleetRepository: any FleetRepository,
            launchService: any LaunchService,
            wait: @escaping (TimeInterval) async -> Void,
            track: @escaping @MainActor (String) -> Void
        ) {
            self.fleetRepository = fleetRepository
            self.launchService = launchService
            self.wait = wait
            self.track = track
        }
    }
}

extension Spaceship.Dependencies {

    /// Wiring for the running app: real components, real waits.
    ///
    /// `track` is passed in rather than built here, so this layer never learns what displays telemetry.
    ///
    /// - Parameter track: Receives a line of telemetry.
    /// - Returns: Dependencies suitable for a real flight.
    public static func live(track: @escaping @MainActor (String) -> Void) -> Self {
        Self(
            fleetRepository: LiveFleetRepository(),
            launchService: LiveLaunchService(),
            wait: { seconds in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            },
            track: track
        )
    }

    /// Wiring that never waits, for tests and previews.
    ///
    /// - Parameters:
    ///   - fleet: The ships the repository returns.
    ///   - track: Where telemetry goes. Defaults to discarding it.
    /// - Returns: Dependencies that resolve immediately, still failing checks for a ship in maintenance
    ///   so the failure branch stays reachable.
    public static func immediate(
        fleet: [Spaceship.Ship] = Spaceship.Ship.demoFleet,
        track: @escaping @MainActor (String) -> Void = { _ in }
    ) -> Self {
        Self(
            fleetRepository: ImmediateFleetRepository(ships: fleet),
            launchService: ImmediateLaunchService(),
            wait: { _ in },
            track: track
        )
    }
}
