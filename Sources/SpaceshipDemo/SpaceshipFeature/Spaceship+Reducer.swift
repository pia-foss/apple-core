import CoreArchitecture
import Foundation

extension Spaceship {

    /// The only place `Spaceship.State` mutates.
    ///
    /// Pure: it captures its dependencies at init and every side effect leaves as an `Effect`. Read it top
    /// to bottom to see all five effect factories, plus every navigation transition.
    public struct Reducer {

        /// Cancellation ids for a flight's long-lived effects.
        ///
        /// An enum rather than string literals, so a typo cannot silently fail to cancel anything.
        private enum EffectID: Hashable {
            case countdown
            case ascent
        }

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
        /// Every branch guards on the phase or path it requires, so an action arriving in a state that
        /// cannot handle it is ignored rather than corrupting the machine.
        ///
        /// - Parameters:
        ///   - state: The state to mutate in place.
        ///   - action: The event to apply.
        /// - Returns: Work to perform, or `nil` when the action needs none.
        public func reduce(_ state: inout State, _ action: Action) -> Effect<Action>? {
            switch action {

            // MARK: - Fleet screen

            case .fleetAppeared:
                // Load once. Coming back from a flight must not refetch.
                guard state.fleet.isEmpty, !state.isLoadingFleet else { return nil }
                state.isLoadingFleet = true
                return .task { [deps] in .fleetLoaded(await deps.fleetRepository.all()) }

            case .fleetLoaded(let ships):
                state.isLoadingFleet = false
                state.fleet = ships
                return nil

            case .shipSelected(let ship):
                // Pushing is a state transition, guarded like any other.
                guard state.path.isEmpty else { return nil }
                // Restore this ship's flight if it has one, so the detail opens on the phase the fleet row
                // just showed.
                if state.flights[ship.id] == nil {
                    state.flights[ship.id] = Flight(ship: ship)
                }
                state.path = [ship.id]
                return .fireAndForget { [deps] in deps.track("Selected \(ship.name)") }

            // MARK: - Navigation container

            case .pathChanged(let newPath):
                guard newPath != state.path else { return nil }
                let departed = Set(state.path).subtracting(newPath)
                // Anything leaving the stack must be grounded. Its effects are cancelled below, so a phase
                // left on `.countdown(2)` would freeze there and the fleet row would claim a countdown that
                // nothing is running. Terminal phases are untouched, so orbit survives going back.
                for id in departed where state.flights[id]?.phase.isInFlight == true {
                    state.flights[id]?.phase = .grounded
                    state.flights[id]?.altitude = 0
                }
                state.path = newPath
                return departed.isEmpty ? nil : cancelFlightWork

            // MARK: - Launch screen

            case .launchTapped:
                // "Not currently flying" rather than "grounded": a ship that reached orbit or failed its
                // checks can try again, so a terminal phase is not a dead end.
                guard let flight = state.flight, !flight.phase.isInFlight else { return nil }
                state.flight?.phase = .runningChecks
                state.flight?.altitude = 0
                let ship = flight.ship
                // `merge` because this action both reports and works. Telemetry leaves as an effect rather
                // than an inline call, which is what keeps this function pure.
                return .merge(
                    .fireAndForget { [deps] in deps.track("Launch requested: \(ship.name)") },
                    .task { [deps] in
                        .checksCompleted(passed: await deps.launchService.preflightChecks(for: ship))
                    }
                )

            case .abortTapped:
                guard let flight = state.flight, flight.phase.isInFlight else { return nil }
                // An abort undoes the launch rather than becoming a state of its own: the ship is ready to
                // fly again, which is also why there is no `.aborted` phase. The stack does not change —
                // aborting is not navigation.
                state.flight?.phase = .grounded
                state.flight?.altitude = 0
                return .merge(
                    cancelFlightWork,
                    .fireAndForget { [deps] in deps.track("Abort: \(flight.ship.name)") }
                )

            // MARK: - Flight effects

            case .checksCompleted(let passed):
                guard state.flight != nil else { return nil }
                guard passed else {
                    state.flight?.phase = .checksFailed(reason: "Ship in maintenance")
                    return .fireAndForget { [deps] in deps.track("Checks failed") }
                }
                state.flight?.phase = .countdown(secondsRemaining: Constants.countdownStart)
                // A stream, because one action cannot express "tick every second, then lift off".
                return .stream(id: EffectID.countdown) { [deps] send in
                    for second in stride(from: Constants.countdownStart - 1, through: 1, by: -1) {
                        await deps.wait(Constants.countdownTick)
                        send(.countdownTicked(secondsRemaining: second))
                    }
                    await deps.wait(Constants.countdownTick)
                    send(.liftoff)
                }

            case .countdownTicked(let secondsRemaining):
                state.flight?.phase = .countdown(secondsRemaining: secondsRemaining)
                return nil

            case .liftoff:
                guard state.flight != nil else { return nil }
                state.flight?.phase = .ascending
                // A second stream under its own id, so an abort can cancel the two independently.
                return .merge(
                    .fireAndForget { [deps] in deps.track("Liftoff") },
                    .stream(id: EffectID.ascent) { [deps] send in
                        for altitude in stride(
                            from: Constants.altitudeStep,
                            through: Constants.orbitAltitude,
                            by: Constants.altitudeStep
                        ) {
                            await deps.wait(Constants.ascentTick)
                            send(.altitudeChanged(altitude))
                        }
                        send(.reachedOrbit)
                    }
                )

            case .altitudeChanged(let altitude):
                state.flight?.altitude = altitude
                return nil

            case .reachedOrbit:
                guard state.flight != nil else { return nil }
                state.flight?.phase = .inOrbit
                return .fireAndForget { [deps] in deps.track("Orbit reached") }
            }
        }

        /// Cancels both of a flight's long-lived effects.
        ///
        /// Safe to return unconditionally: `cancel` is a no-op when nothing is running under an id.
        private var cancelFlightWork: Effect<Action> {
            .merge(
                .cancel(id: EffectID.countdown),
                .cancel(id: EffectID.ascent)
            )
        }
    }
}

extension Spaceship.Reducer {

    /// The numbers governing a flight's shape and pace.
    ///
    /// Gathered here so the reducer body reads as transitions rather than arithmetic. Kept `private`
    /// because a test should assert the countdown starts at three by watching the phases, not by reading
    /// the constant that produced them.
    private enum Constants {

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
