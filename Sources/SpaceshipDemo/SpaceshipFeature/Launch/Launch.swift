import CoreArchitecture
import Foundation

/// Namespace for the launch feature: fly one ship, or abort.
///
/// The second of the demo's two features, and the reason it is separate: it owns a state machine and two
/// long-lived effects that no other screen has any business seeing. Its store is created when the launch
/// screen is pushed and released when the screen goes away.
public enum Launch {}

extension Launch {

    /// Everything the launch screen renders.
    ///
    /// One ship, one attempt. There is no dictionary and no navigation here — this feature knows about
    /// exactly the flight it was created for.
    public struct State: Equatable {

        /// The ship being launched.
        public let ship: Spaceship.Ship

        /// How far the attempt has got.
        public var phase: Spaceship.Phase

        /// Altitude in kilometres, zero until ascent begins.
        public var altitude: Int

        /// Creates a launch state for `ship`.
        ///
        /// - Parameters:
        ///   - ship: The ship being launched.
        ///   - phase: The phase to start in. The flow seeds this from the fleet's last recorded result, so
        ///     reopening a ship that reached orbit does not claim it is grounded.
        ///   - altitude: Altitude in kilometres.
        public init(ship: Spaceship.Ship, phase: Spaceship.Phase = .grounded, altitude: Int = 0) {
            self.ship = ship
            self.phase = phase
            self.altitude = altitude
        }
    }

    /// Every event the launch feature can receive.
    public enum Action: Equatable {

        // MARK: - Launch screen

        case launchTapped
        case abortTapped

        // MARK: - From effects

        /// Pre-flight checks finished, carrying whether they passed.
        case checksCompleted(passed: Bool)
        /// The countdown reached a new second.
        case countdownTicked(secondsRemaining: Int)
        case liftoff
        /// The ship passed a new altitude, in kilometres.
        case altitudeChanged(Int)
        case reachedOrbit
    }

    /// The collaborators that keep `Launch.Reducer` pure.
    ///
    /// Only three, and none of them is a repository: this feature fetches nothing. Each feature declaring
    /// its own dependencies is what stops one screen's collaborators leaking into another's.
    public struct Dependencies {

        /// The rules deciding whether a ship may fly.
        public var launchService: any LaunchService

        /// Suspends for a number of seconds.
        public var wait: (TimeInterval) async -> Void

        /// Sends a line of telemetry to ground control.
        public var track: @MainActor (String) -> Void

        /// Reports a final phase to whoever is listening.
        ///
        /// Reporting upward is a side effect like any other, so it is a dependency rather than a closure
        /// threaded through the view. The flow wires it to the fleet's store; a test passes a spy. Neither
        /// the reducer nor the screen learns that a fleet exists.
        public var reportResult: @MainActor (Spaceship.Phase) -> Void

        /// Creates a dependency set.
        ///
        /// - Parameters:
        ///   - launchService: The rules deciding whether a ship may fly.
        ///   - wait: Suspends for a number of seconds.
        ///   - track: Receives a line of telemetry.
        ///   - reportResult: Receives a final phase.
        public init(
            launchService: any LaunchService,
            wait: @escaping (TimeInterval) async -> Void,
            track: @escaping @MainActor (String) -> Void,
            reportResult: @escaping @MainActor (Spaceship.Phase) -> Void
        ) {
            self.launchService = launchService
            self.wait = wait
            self.track = track
            self.reportResult = reportResult
        }
    }
}

extension Launch.Dependencies {

    /// Wiring for the running app: real checks, real waits.
    ///
    /// - Parameters:
    ///   - track: Receives a line of telemetry.
    ///   - reportResult: Receives a final phase.
    /// - Returns: Dependencies suitable for a real flight.
    public static func live(
        track: @escaping @MainActor (String) -> Void,
        reportResult: @escaping @MainActor (Spaceship.Phase) -> Void
    ) -> Self {
        Self(
            launchService: LiveLaunchService(),
            wait: { seconds in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            },
            track: track,
            reportResult: reportResult
        )
    }

    /// Wiring that never waits, for tests and previews.
    ///
    /// - Parameters:
    ///   - track: Where telemetry goes. Defaults to discarding it.
    ///   - reportResult: Where results go. Defaults to discarding them.
    /// - Returns: Dependencies that resolve immediately, still failing checks for a ship in maintenance so
    ///   the failure branch stays reachable.
    public static func immediate(
        track: @escaping @MainActor (String) -> Void = { _ in },
        reportResult: @escaping @MainActor (Spaceship.Phase) -> Void = { _ in }
    ) -> Self {
        Self(
            launchService: ImmediateLaunchService(),
            wait: { _ in },
            track: track,
            reportResult: reportResult
        )
    }
}
