import Foundation

/// The domain rules governing whether a ship may fly.
///
/// A Service rather than a Repository because it decides something rather than fetching something, and a
/// protocol rather than a closure because the rule is the kind that grows: today it reads one flag,
/// tomorrow it consults weather, range, and crew certification.
public protocol LaunchService {

    /// Whether `ship` passes its pre-flight checks.
    ///
    /// - Parameter ship: The ship about to launch.
    /// - Returns: `true` when the ship may fly.
    func preflightChecks(for ship: Spaceship.Ship) async -> Bool
}

/// The service the running app uses.
public struct LiveLaunchService: LaunchService {

    /// Creates the service.
    public init() {}

    /// Waits first, so the `runningChecks` phase is long enough to see.
    public func preflightChecks(for ship: Spaceship.Ship) async -> Bool {
        try? await Task.sleep(nanoseconds: 600_000_000)
        return ship.readiness == .ready
    }
}

/// A service that answers at once, for tests and previews.
public struct ImmediateLaunchService: LaunchService {

    /// Creates the service.
    public init() {}

    /// Applies the same rule without suspending.
    public func preflightChecks(for ship: Spaceship.Ship) async -> Bool {
        ship.readiness == .ready
    }
}
