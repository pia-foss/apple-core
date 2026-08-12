import CoreArchitecture
import Foundation

extension Spaceship {

    /// The only place `Spaceship.State` mutates.
    ///
    /// Pure: it captures its dependencies at init and every side effect leaves as an `Effect`. Read it
    /// top to bottom to see all five effect factories in use.
    public struct Reducer {

        /// Cancellation ids for the flight's long-lived effects.
        ///
        /// An enum rather than string literals, so a typo cannot silently fail to cancel anything.
        private enum EffectID: Hashable {
            case countdown
            case ascent
        }

        /// Seconds the countdown starts from.
        private static let countdownStart = 3

        /// Altitude in kilometres at which the flight reaches orbit.
        private static let orbitAltitude = 100

        /// The injected collaborators.
        ///
        /// Captured once at init, so no effect ever reaches for a global.
        public let deps: Dependencies

        /// Creates a reducer bound to `deps`.
        ///
        /// - Parameter deps: The collaborators every effect runs through.
        public init(deps: Dependencies) {
            self.deps = deps
        }

        /// Applies `action` to `state` and returns any work that should follow.
        ///
        /// - Parameters:
        ///   - state: The state to mutate in place.
        ///   - action: The event to apply.
        /// - Returns: Work to perform, or `nil` when the action needs none.
        public func reduce(_ state: inout State, _ action: Action) -> Effect<Action>? {
            switch action {

            case .launchTapped:
                // Ignore a second tap rather than starting a second countdown.
                guard state.phase == .grounded else { return nil }
                state.phase = .runningChecks
                // `merge` because this action both reports and works. Telemetry leaves as an effect
                // rather than an inline call, which is what keeps this function pure.
                return .merge(
                    .fireAndForget { [deps] in deps.track("Launch requested") },
                    .task { [deps] in .checksCompleted(passed: await deps.runPreflightChecks()) }
                )

            case .checksCompleted(let passed):
                guard passed else {
                    state.phase = .checksFailed(reason: "Fuel pressure low")
                    return .fireAndForget { [deps] in deps.track("Checks failed") }
                }
                state.phase = .countdown(secondsRemaining: Self.countdownStart)
                // A stream, because one action cannot express "tick every second, then lift off".
                return .stream(id: EffectID.countdown) { [deps] send in
                    for second in stride(from: Self.countdownStart - 1, through: 1, by: -1) {
                        await deps.wait(1)
                        send(.countdownTicked(secondsRemaining: second))
                    }
                    await deps.wait(1)
                    send(.liftoff)
                }

            case .countdownTicked(let secondsRemaining):
                state.phase = .countdown(secondsRemaining: secondsRemaining)
                return nil

            case .liftoff:
                state.phase = .ascending
                // A second stream under its own id, so an abort can cancel the two independently.
                return .merge(
                    .fireAndForget { [deps] in deps.track("Liftoff") },
                    .stream(id: EffectID.ascent) { [deps] send in
                        for altitude in stride(from: 20, through: Self.orbitAltitude, by: 20) {
                            await deps.wait(0.4)
                            send(.altitudeChanged(altitude))
                        }
                        send(.reachedOrbit)
                    }
                )

            case .altitudeChanged(let altitude):
                state.altitude = altitude
                return nil

            case .reachedOrbit:
                state.phase = .inOrbit
                return .fireAndForget { [deps] in deps.track("Orbit reached") }

            case .abortTapped:
                guard state.phase.isInFlight else { return nil }
                state.phase = .aborted
                state.altitude = 0
                return .merge(
                    .cancel(id: EffectID.countdown),
                    .cancel(id: EffectID.ascent),
                    .fireAndForget { [deps] in deps.track("Abort") }
                )

            case .resetTapped:
                state = State()
                // Cancelling defensively is safe: `cancel` is a no-op when nothing is in flight.
                return .merge(
                    .cancel(id: EffectID.countdown),
                    .cancel(id: EffectID.ascent)
                )
            }
        }
    }
}
