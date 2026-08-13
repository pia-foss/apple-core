import CoreArchitecture
import XCTest

@testable import SpaceshipDemo

/// The launch feature, tested on its own.
///
/// Every test constructs a state for one ship — no fleet, no navigation, no dictionary to index. That is
/// what a store per feature buys the tests as well as the code.
@MainActor
final class LaunchReducerTests: XCTestCase {

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

    func test_launch_whileAlreadyFlying_isIgnored() {
        var state = Launch.State(ship: atlas, phase: .ascending, altitude: 40)

        XCTAssertNil(makeReducer().reduce(&state, .launchTapped))
        XCTAssertEqual(state.phase, .ascending)
    }

    /// A terminal phase is not a dead end: the guard is "not currently flying", not "grounded".
    func test_launchAgain_fromOrbit_isAllowed() {
        var state = Launch.State(ship: atlas, phase: .inOrbit, altitude: 100)

        XCTAssertNotNil(makeReducer().reduce(&state, .launchTapped))
        XCTAssertEqual(state.phase, .runningChecks)
        XCTAssertEqual(state.altitude, 0)
    }

    func test_abort_whileGrounded_isIgnored() {
        var state = Launch.State(ship: atlas)

        XCTAssertNil(makeReducer().reduce(&state, .abortTapped))
        XCTAssertEqual(state.phase, .grounded)
    }

    func test_abort_returnsTheShipToGrounded() {
        var state = Launch.State(ship: atlas, phase: .ascending, altitude: 60)

        XCTAssertNotNil(makeReducer().reduce(&state, .abortTapped))
        XCTAssertEqual(state.phase, .grounded)
        XCTAssertEqual(state.altitude, 0)
    }

    // MARK: - Seeding from the fleet's record

    /// Reopening a ship that reached orbit does not claim it is grounded.
    ///
    /// The flow seeds this from `Fleet.State.results`, which is how two stores stay consistent without
    /// either one mirroring the other.
    func test_aSeededPhaseIsHonoured() {
        let state = Launch.State(ship: atlas, phase: .inOrbit, altitude: 100)

        XCTAssertEqual(state.phase, .inOrbit)
        XCTAssertFalse(state.phase.isInFlight)
    }

    // MARK: - Async round-trips

    func test_shipInMaintenance_failsItsChecks() async {
        let store = makeStore(ship: cygnus)

        store.send(.launchTapped)
        let received = await store.receive()

        XCTAssertEqual(received, .checksCompleted(passed: false))
        XCTAssertEqual(store.state.phase, .checksFailed(reason: "Ship in maintenance"))
    }

    /// Walks a whole flight, one effect-produced action at a time.
    ///
    /// Under a plain `Store` these phases would flash past in microseconds, so a test could only check the
    /// final state — and would still pass if the countdown never ticked at all.
    func test_fullFlight_reachesOrbit() async {
        let store = makeStore(ship: atlas)

        store.send(.launchTapped)
        XCTAssertEqual(store.state.phase, .runningChecks)

        await assertReceives(.checksCompleted(passed: true), on: store)
        XCTAssertEqual(store.state.phase, .countdown(secondsRemaining: 3))

        await assertReceives(.countdownTicked(secondsRemaining: 2), on: store)
        await assertReceives(.countdownTicked(secondsRemaining: 1), on: store)

        await assertReceives(.liftoff, on: store)
        XCTAssertEqual(store.state.phase, .ascending)

        for altitude in stride(from: 20, through: 100, by: 20) {
            await assertReceives(.altitudeChanged(altitude), on: store)
            XCTAssertEqual(store.state.altitude, altitude)
        }

        await assertReceives(.reachedOrbit, on: store)
        XCTAssertEqual(store.state.phase, .inOrbit)
    }

    // MARK: - Reporting upward

    /// The launch reports its result outward without knowing who listens.
    ///
    /// `reportResult` is a dependency, so this asserts on a spy exactly as it does for telemetry. In the app
    /// the flow wires the same closure to `Fleet.Action.flightFinished`.
    func test_reachingOrbit_reportsTheResult() async {
        let spy = Spy()
        let store = makeStore(ship: atlas, phase: .ascending, spy: spy)

        store.send(.reachedOrbit)
        await store.finish()

        XCTAssertEqual(spy.results, [.inOrbit])
        XCTAssertEqual(spy.telemetry, ["Orbit reached"])
    }

    func test_failedChecks_reportTheResult() async {
        let spy = Spy()
        let store = makeStore(ship: cygnus, spy: spy)

        store.send(.launchTapped)
        _ = await store.receive()  // .checksCompleted(passed: false)
        await store.finish()

        XCTAssertEqual(spy.results, [.checksFailed(reason: "Ship in maintenance")])
    }

    /// An interrupted flight reports nothing.
    ///
    /// Only final phases go upward, so walking away mid-countdown leaves the fleet's record untouched
    /// rather than freezing it on a countdown nothing is running.
    func test_abort_reportsNoResult() async {
        let spy = Spy()
        let store = makeStore(ship: atlas, phase: .ascending, spy: spy)

        store.send(.abortTapped)
        await store.finish()

        XCTAssertTrue(spy.results.isEmpty)
        XCTAssertEqual(spy.telemetry, ["Abort: Atlas"])
    }

    // MARK: - Helpers

    private func assertReceives(
        _ expected: Launch.Action,
        on store: TestStore<Launch.State, Launch.Action>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let received = await store.receive()
        XCTAssertEqual(received, expected, file: file, line: line)
    }
}
