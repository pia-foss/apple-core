import Foundation

/// Where the fleet comes from.
///
/// A Repository rather than a closure because it owns a *decision* — network, cache, or disk — and is the
/// kind of collaborator more than one feature ends up wanting. A protocol keeps it navigable: every
/// implementation is one jump from here.
public protocol FleetRepository {

    /// The ships available to launch.
    func all() async -> [Spaceship.Ship]
}

/// The repository the running app uses.
public struct LiveFleetRepository: FleetRepository {

    /// Creates the repository.
    public init() {}

    /// Waits first, standing in for a network round trip, so the loading state is visible rather than
    /// theoretical.
    public func all() async -> [Spaceship.Ship] {
        try? await Task.sleep(nanoseconds: 400_000_000)
        return Spaceship.Ship.demoFleet
    }
}

/// A repository that answers at once, for tests and previews.
public struct ImmediateFleetRepository: FleetRepository {

    private let ships: [Spaceship.Ship]

    /// Creates a repository that always returns `ships`.
    ///
    /// - Parameter ships: The fleet to hand back.
    public init(ships: [Spaceship.Ship] = Spaceship.Ship.demoFleet) {
        self.ships = ships
    }

    /// Returns the fixed fleet without suspending.
    public func all() async -> [Spaceship.Ship] {
        ships
    }
}
