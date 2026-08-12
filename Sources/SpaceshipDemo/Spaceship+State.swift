import Foundation

extension Spaceship {

    /// Everything the launch screen renders, and the single source of truth for a flight.
    public struct State: Equatable {

        /// Where the flight is in its lifecycle.
        ///
        /// One enum rather than a set of booleans is the point of the exercise: there is no way to
        /// represent "counting down while already in orbit", so no view can render it.
        public enum Phase: Equatable {
            case grounded
            case runningChecks
            /// Counting down, holding the seconds still to go.
            case countdown(secondsRemaining: Int)
            case ascending
            case inOrbit
            case aborted
            /// Pre-flight checks failed, carrying the reason to show the pilot.
            case checksFailed(reason: String)
        }

        /// The flight's current phase.
        public var phase: Phase

        /// Altitude in kilometres.
        ///
        /// Zero on the ground and after an abort.
        public var altitude: Int

        /// Creates a flight state, defaulting to a grounded spaceship.
        ///
        /// - Parameters:
        ///   - phase: The phase to start in. Tests use this to jump straight to the case under test.
        ///   - altitude: Altitude in kilometres.
        public init(phase: Phase = .grounded, altitude: Int = 0) {
            self.phase = phase
            self.altitude = altitude
        }
    }
}

extension Spaceship.State.Phase {

    /// Whether a long-lived effect is running for this phase.
    ///
    /// Aborting is only meaningful here, so the reducer uses it to ignore a stray abort rather than
    /// cancelling effects that were never started.
    public var isInFlight: Bool {
        switch self {
        case .runningChecks, .countdown, .ascending:
            return true
        case .grounded, .inOrbit, .aborted, .checksFailed:
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
        case .aborted: return "Launch aborted"
        case .checksFailed(let reason): return "Checks failed: \(reason)"
        }
    }
}
