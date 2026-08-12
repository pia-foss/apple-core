import Foundation

extension Spaceship {

    /// One ship's launch attempt.
    ///
    /// Kept per ship in `State.flights`, so the fleet list and the launch screen read the same value and
    /// cannot disagree about what a ship is doing.
    public struct Flight: Equatable {

        /// Where the launch attempt has got to.
        ///
        /// The transitions are the feature: `grounded → runningChecks → countdown → ascending →
        /// inOrbit`, with `checksFailed` as the early exit. Aborting is not a phase — it returns the
        /// ship to `grounded`.
        public enum Phase: Equatable {
            case grounded
            case runningChecks
            /// Counting down, holding the seconds still to go.
            case countdown(secondsRemaining: Int)
            case ascending
            case inOrbit
            /// Pre-flight checks failed, carrying the reason to show the pilot.
            case checksFailed(reason: String)
        }

        /// The ship being launched.
        public let ship: Ship

        /// How far the launch attempt has got.
        public var phase: Phase

        /// Altitude in kilometres, zero until ascent begins.
        public var altitude: Int

        /// Creates a flight for `ship`, grounded unless told otherwise.
        ///
        /// - Parameters:
        ///   - ship: The ship being launched.
        ///   - phase: The phase to start in. Tests use this to jump to the case under test.
        ///   - altitude: Altitude in kilometres.
        public init(ship: Ship, phase: Phase = .grounded, altitude: Int = 0) {
            self.ship = ship
            self.phase = phase
            self.altitude = altitude
        }
    }
}

extension Spaceship.Flight.Phase {

    /// Whether a long-lived effect is running for this phase.
    ///
    /// Aborting and leaving the screen both use it to decide whether there is anything to cancel.
    public var isInFlight: Bool {
        switch self {
        case .runningChecks, .countdown, .ascending:
            return true
        case .grounded, .inOrbit, .checksFailed:
            return false
        }
    }

    /// A short label for the phase, ready to render.
    public var title: String {
        switch self {
        case .grounded: return "Ready for launch"
        case .runningChecks: return "Running pre-flight checks"
        case .countdown(let seconds): return "T-minus \(seconds)"
        case .ascending: return "Ascending"
        case .inOrbit: return "In orbit"
        case .checksFailed(let reason): return "Checks failed: \(reason)"
        }
    }

    /// A short label for the fleet list, or `nil` when the ship has nothing to report.
    public var fleetLabel: String? {
        switch self {
        case .grounded: return nil
        case .runningChecks: return "checking"
        case .countdown: return "counting down"
        case .ascending: return "ascending"
        case .inOrbit: return "in orbit"
        case .checksFailed: return "checks failed"
        }
    }
}
