import CoreArchitecture
import Foundation

extension Launch {

    /// The only place `Launch.State` mutates.
    ///
    /// Pure: it captures its dependencies at init and every side effect leaves as an `Effect`. `reduce` is
    /// a routing table — read it for the whole action surface, then the handler for the transition you
    /// care about.
    public struct Reducer {

        /// The state this reducer moves.
        public typealias State = Launch.State

        /// The events this reducer accepts.
        public typealias Action = Launch.Action

        /// Cancellation ids for the flight's long-lived effects.
        ///
        /// An enum rather than string literals, so a typo cannot silently fail to cancel anything.
        fileprivate enum EffectID: Hashable {
            case countdown
            case ascent
        }

        /// The injected collaborators.
        public let dependencies: Dependencies

        /// Creates a reducer bound to `dependencies`.
        ///
        /// - Parameter dependencies: The collaborators every effect runs through.
        public init(dependencies: Dependencies) {
            self.dependencies = dependencies
        }

        /// Applies `action` to `state` and returns any work that should follow.
        ///
        /// - Parameters:
        ///   - state: The state to mutate in place.
        ///   - action: The event to apply.
        /// - Returns: Work to perform, or `nil` when the action needs none.
        public func reduce(_ state: inout State, _ action: Action) -> Effect<Action>? {
            switch action {
            case .launchTapped: return begin(in: &state)
            case .abortTapped: return abort(in: &state)
            case .checksCompleted(let passed): return finishChecks(passed: passed, in: &state)
            case .countdownTicked(let seconds): return tick(to: seconds, in: &state)
            case .liftoff: return ascend(in: &state)
            case .altitudeChanged(let altitude): return climb(to: altitude, in: &state)
            case .reachedOrbit: return enterOrbit(in: &state)
            }
        }
    }
}

extension Launch.Reducer {

    /// Starts pre-flight checks.
    ///
    /// The guard is "not currently flying" rather than "grounded", so a ship that reached orbit or failed
    /// its checks can try again and a terminal phase is not a dead end.
    private func begin(in state: inout State) -> Effect<Action>? {
        guard !state.phase.isInFlight else { return nil }
        state.phase = .runningChecks
        state.altitude = 0
        let ship = state.ship
        // `merge` because this action both reports and works. Telemetry leaves as an effect rather than an
        // inline call, which is what keeps this function pure.
        return .merge(
            .fireAndForget { [dependencies] in dependencies.track("Launch requested: \(ship.name)") },
            .task { [dependencies] in
                .checksCompleted(passed: await dependencies.launchService.preflightChecks(for: ship))
            }
        )
    }

    /// Returns the ship to the ground.
    ///
    /// An abort undoes the launch rather than becoming a state of its own, which is why there is no
    /// `.aborted` phase.
    private func abort(in state: inout State) -> Effect<Action>? {
        guard state.phase.isInFlight else { return nil }
        state.phase = .grounded
        state.altitude = 0
        let name = state.ship.name
        return .merge(
            cancelFlightWork,
            .fireAndForget { [dependencies] in dependencies.track("Abort: \(name)") }
        )
    }

    /// Starts the countdown, or reports why the ship cannot fly.
    private func finishChecks(passed: Bool, in state: inout State) -> Effect<Action>? {
        guard passed else {
            let failed = Spaceship.Phase.checksFailed(reason: "Ship in maintenance")
            state.phase = failed
            return report(failed, telemetry: "Checks failed")
        }
        state.phase = .countdown(secondsRemaining: Constants.countdownStart)
        // A stream, because one action cannot express "tick every second, then lift off".
        return .stream(id: EffectID.countdown) { [dependencies] send in
            for second in stride(from: Constants.countdownStart - 1, through: 1, by: -1) {
                await dependencies.wait(Constants.countdownTick)
                send(.countdownTicked(secondsRemaining: second))
            }
            await dependencies.wait(Constants.countdownTick)
            send(.liftoff)
        }
    }

    private func tick(to secondsRemaining: Int, in state: inout State) -> Effect<Action>? {
        state.phase = .countdown(secondsRemaining: secondsRemaining)
        return nil
    }

    /// Lifts off and starts reporting altitude.
    ///
    /// The ascent runs under its own id, so an abort can cancel it and the countdown independently.
    private func ascend(in state: inout State) -> Effect<Action>? {
        state.phase = .ascending
        return .merge(
            .fireAndForget { [dependencies] in dependencies.track("Liftoff") },
            .stream(id: EffectID.ascent) { [dependencies] send in
                for altitude in stride(
                    from: Constants.altitudeStep,
                    through: Constants.orbitAltitude,
                    by: Constants.altitudeStep
                ) {
                    await dependencies.wait(Constants.ascentTick)
                    send(.altitudeChanged(altitude))
                }
                send(.reachedOrbit)
            }
        )
    }

    private func climb(to altitude: Int, in state: inout State) -> Effect<Action>? {
        state.altitude = altitude
        return nil
    }

    private func enterOrbit(in state: inout State) -> Effect<Action>? {
        state.phase = .inOrbit
        return report(.inOrbit, telemetry: "Orbit reached")
    }

    /// Reports a final phase upward and logs it, in one effect.
    ///
    /// Only final phases are reported, so walking away mid-countdown leaves the fleet's record untouched
    /// rather than freezing it on a countdown nothing is running.
    ///
    /// - Parameters:
    ///   - phase: The phase reached. Must satisfy `isFinal`.
    ///   - telemetry: The line to log alongside it.
    /// - Returns: An effect that reports and logs, producing no action.
    private func report(_ phase: Spaceship.Phase, telemetry: String) -> Effect<Action> {
        .fireAndForget { [dependencies] in
            dependencies.track(telemetry)
            dependencies.reportResult(phase)
        }
    }
}

extension Launch.Reducer {

    /// Cancels both of the flight's long-lived effects.
    ///
    /// Safe to return unconditionally: `cancel` is a no-op when nothing is running under an id.
    fileprivate var cancelFlightWork: Effect<Action> {
        .merge(
            .cancel(id: EffectID.countdown),
            .cancel(id: EffectID.ascent)
        )
    }

    /// The numbers governing the flight's shape and pace.
    fileprivate enum Constants {

        /// Seconds the countdown starts from.
        static let countdownStart = 3

        /// Seconds between countdown ticks.
        static let countdownTick: TimeInterval = 1

        /// Altitude in kilometres at which the flight reaches orbit.
        static let orbitAltitude = 100

        /// Kilometres gained per ascent tick.
        static let altitudeStep = 20

        /// Seconds between ascent ticks.
        static let ascentTick: TimeInterval = 0.4
    }
}
