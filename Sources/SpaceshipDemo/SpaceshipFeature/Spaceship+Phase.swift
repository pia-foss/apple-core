import Foundation

extension Spaceship {

    /// Where a launch attempt has got to.
    ///
    /// Shared domain rather than a feature's own type: `Launch` moves a ship through these, and `Fleet`
    /// remembers the last one it was told about. Aborting is not a phase — it returns the ship to
    /// `grounded`.
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
}

extension Spaceship.Phase {

    /// Whether a long-lived effect is running for this phase.
    public var isInFlight: Bool {
        switch self {
        case .runningChecks, .countdown, .ascending:
            return true
        case .grounded, .inOrbit, .checksFailed:
            return false
        }
    }

    /// Whether the phase is a result worth reporting to the fleet.
    ///
    /// The launch feature reports only these upward, so an attempt the pilot walked away from leaves the
    /// fleet's record untouched rather than freezing it mid-countdown.
    public var isFinal: Bool {
        switch self {
        case .inOrbit, .checksFailed:
            return true
        case .grounded, .runningChecks, .countdown, .ascending:
            return false
        }
    }

    /// A short label for the launch screen, ready to render.
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
        case .grounded, .runningChecks, .countdown, .ascending: return nil
        case .inOrbit: return "in orbit"
        case .checksFailed: return "checks failed"
        }
    }
}
