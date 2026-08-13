import CoreArchitecture
import Foundation

/// Namespace for the fleet feature: load the ships and show them.
///
/// Notice how little it owns. Navigation and launch results moved to `Flow` because neither is the fleet's
/// to decide or produce, and what remains is one screen's own state — which is exactly the amount a feature
/// store should hold.
public enum Fleet {}

extension Fleet {

    /// Everything the fleet screen owns.
    public struct State: Equatable {

        /// The ships available to launch.
        public var ships: [Spaceship.Ship]

        /// Whether the list is still loading.
        public var isLoading: Bool

        /// Creates a fleet state, defaulting to an empty list.
        ///
        /// - Parameters:
        ///   - ships: The ships available to launch.
        ///   - isLoading: Whether the list is still loading.
        public init(ships: [Spaceship.Ship] = [], isLoading: Bool = false) {
            self.ships = ships
            self.isLoading = isLoading
        }
    }

    /// Every event the fleet feature can receive.
    ///
    /// There is no `shipSelected` here: the screen reports a selection through an output closure, and `Flow`
    /// decides what it means. A screen never knows what comes next.
    public enum Action: Equatable {
        case appeared
        case shipsLoaded([Spaceship.Ship])
    }

    /// The collaborators that keep `Fleet.Reducer` pure.
    ///
    /// One, because the feature does one thing.
    public struct Dependencies {

        /// Where the fleet comes from.
        public var fleetRepository: any FleetRepository

        /// Creates a dependency set.
        ///
        /// - Parameter fleetRepository: Where the fleet comes from.
        public init(fleetRepository: any FleetRepository) {
            self.fleetRepository = fleetRepository
        }
    }
}

extension Fleet.Dependencies {

    /// Wiring for the running app.
    public static var live: Self {
        Self(fleetRepository: LiveFleetRepository())
    }

    /// Wiring that answers at once, for tests and previews.
    ///
    /// - Parameter ships: The ships the repository returns.
    /// - Returns: Dependencies that resolve immediately.
    public static func immediate(ships: [Spaceship.Ship] = Spaceship.Ship.demoFleet) -> Self {
        Self(fleetRepository: ImmediateFleetRepository(ships: ships))
    }
}
