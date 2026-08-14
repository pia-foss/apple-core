import CoreArchitecture
import Testing

@testable import SpaceshipDemo

/// The launch feature, tested on its own.
///
/// Every test constructs a state for one ship — no fleet, no navigation, no dictionary to index. That is
/// what a store per feature buys the tests as well as the code.
@MainActor
struct LaunchReducerTests {

    private let atlas = Spaceship.Ship(id: "atlas", name: "Atlas", readiness: .ready)
    private let cygnus = Spaceship.Ship(id: "cygnus", name: "Cygnus", readiness: .inMaintenance)

    private func makeReducer() -> Launch.Reducer {
        Launch.Reducer(dependencies: .immediate())
    }

    private func makeStore(
        ship: Spaceship.Ship,
        phase: Spaceship.Phase = .grounded,
        spy: Spy? = nil
    ) -> TestStore<Launch.State, Launch.Action> {
        let sink = spy ?? Spy()
        return TestStore(
            initial: Launch.State(ship: ship, phase: phase),
            reduce: Launch.Reducer(
                dependencies: .immediate(track: sink.track, reportResult: sink.report)
            ).reduce
        )
    }

    // MARK: - Guards

    @Test
    func launchWhileAlreadyFlyingIsIgnored() {
        var state = Launch.State(ship: atlas, phase: .ascending, altitude: 40)

        #expect(makeReducer().reduce(&state, .launchTapped) == nil)
        #expect(state.phase == .ascending)
    }

    /// A terminal phase is not a dead end: the guard is "not currently flying", not "grounded".
    @Test
    func launchAgainFromOrbitIsAllowed() {
        var state = Launch.State(ship: atlas, phase: .inOrbit, altitude: 100)

        #expect(makeReducer().reduce(&state, .launchTapped) != nil)
        #expect(state.phase == .runningChecks)
        #expect(state.altitude == 0)
    }

    @Test
    func abortWhileGroundedIsIgnored() {
        var state = Launch.State(ship: atlas)

        #expect(makeReducer().reduce(&state, .abortTapped) == nil)
        #expect(state.phase == .grounded)
    }

    @Test
    func abortReturnsTheShipToGrounded() {
        var state = Launch.State(ship: atlas, phase: .ascending, altitude: 60)

        #expect(makeReducer().reduce(&state, .abortTapped) != nil)
        #expect(state.phase == .grounded)
        #expect(state.altitude == 0)
    }

    // MARK: - Seeding from the fleet's record

    /// Reopening a ship that reached orbit does not claim it is grounded.
    ///
    /// The flow seeds this from `Fleet.State.results`, which is how two stores stay consistent without
    /// either one mirroring the other.
    @Test
    func aSeededPhaseIsHonoured() {
        let state = Launch.State(ship: atlas, phase: .inOrbit, altitude: 100)

        #expect(state.phase == .inOrbit)
        #expect(state.phase.isInFlight == false)
    }

    // MARK: - Async round-trips

    @Test
    func shipInMaintenanceFailsItsChecks() async {
        let store = makeStore(ship: cygnus)

        store.send(.launchTapped)
        let received = await store.receive()

        #expect(received == .checksCompleted(passed: false))
        #expect(store.state.phase == .checksFailed(reason: "Ship in maintenance"))
    }

    /// Walks a whole flight, one effect-produced action at a time.
    ///
    /// Under a plain `Store` these phases would flash past in microseconds, so a test could only check the
    /// final state — and would still pass if the countdown never ticked at all.
    @Test
    func fullFlightReachesOrbit() async {
        let store = makeStore(ship: atlas)

        store.send(.launchTapped)
        #expect(store.state.phase == .runningChecks)

        await assertReceives(.checksCompleted(passed: true), on: store)
        #expect(store.state.phase == .countdown(secondsRemaining: 3))

        await assertReceives(.countdownTicked(secondsRemaining: 2), on: store)
        await assertReceives(.countdownTicked(secondsRemaining: 1), on: store)

        await assertReceives(.liftoff, on: store)
        #expect(store.state.phase == .ascending)

        for altitude in stride(from: 20, through: 100, by: 20) {
            await assertReceives(.altitudeChanged(altitude), on: store)
            #expect(store.state.altitude == altitude)
        }

        await assertReceives(.reachedOrbit, on: store)
        #expect(store.state.phase == .inOrbit)
    }

    // MARK: - Reporting upward

    /// The launch reports its result outward without knowing who listens.
    ///
    /// `reportResult` is a dependency, so this asserts on a spy exactly as it does for telemetry. In the app
    /// the flow wires the same closure to `Fleet.Action.flightFinished`.
    @Test
    func reachingOrbitReportsTheResult() async {
        let spy = Spy()
        let store = makeStore(ship: atlas, phase: .ascending, spy: spy)

        store.send(.reachedOrbit)
        await store.finish()

        #expect(spy.results == [.inOrbit])
        #expect(spy.telemetry == ["Orbit reached"])
    }

    @Test
    func failedChecksReportTheResult() async {
        let spy = Spy()
        let store = makeStore(ship: cygnus, spy: spy)

        store.send(.launchTapped)
        _ = await store.receive()  // .checksCompleted(passed: false)
        await store.finish()

        #expect(spy.results == [.checksFailed(reason: "Ship in maintenance")])
    }

    /// An interrupted flight reports nothing.
    ///
    /// Only final phases go upward, so walking away mid-countdown leaves the fleet's record untouched
    /// rather than freezing it on a countdown nothing is running.
    @Test
    func abortReportsNoResult() async {
        let spy = Spy()
        let store = makeStore(ship: atlas, phase: .ascending, spy: spy)

        store.send(.abortTapped)
        await store.finish()

        #expect(spy.results.isEmpty)
        #expect(spy.telemetry == ["Abort: Atlas"])
    }

    // MARK: - Helpers

    private func assertReceives(
        _ expected: Launch.Action,
        on store: TestStore<Launch.State, Launch.Action>,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        let received = await store.receive()
        #expect(received == expected, sourceLocation: sourceLocation)
    }
}
