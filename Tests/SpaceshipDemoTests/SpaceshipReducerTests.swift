import CoreArchitecture
import XCTest

@testable import SpaceshipDemo

/// Shows both ways to test a reducer.
///
/// Claims about a synchronous mutation, a navigation transition, or *whether* an effect came back go
/// straight to the reducer — it is a pure function, so no runtime is needed. Claims about an async
/// round-trip go through `TestStore`. The runtime's own cancellation semantics belong to the library's
/// tests and are not re-proven here.
@MainActor
final class SpaceshipReducerTests: XCTestCase {

    private let atlas = Spaceship.Ship(id: "atlas", name: "Atlas", readiness: .ready)
    private let cygnus = Spaceship.Ship(id: "cygnus", name: "Cygnus", readiness: .inMaintenance)

    private func makeReducer() -> Spaceship.Reducer {
        Spaceship.Reducer(deps: .immediate())
    }

    /// Records telemetry so a test can prove what the reducer reported.
    ///
    /// Hand-rolled here rather than borrowed from the UI target: these tests cover the feature layer, and
    /// reaching across the boundary for a convenience type is exactly what the target split prevents.
    @MainActor
    private final class TelemetrySpy {

        private(set) var entries: [String] = []

        func record(_ message: String) {
            entries.append(message)
        }
    }

    /// Builds a test store already on the launch screen for `flight`.
    ///
    /// The spy is created here rather than defaulted, because a default argument is evaluated in a
    /// nonisolated context and `TelemetrySpy` is main-actor isolated.
    private func makeLaunchStore(
        _ flight: Spaceship.Flight,
        spy: TelemetrySpy? = nil
    ) -> TestStore<Spaceship.State, Spaceship.Action> {
        let sink = spy ?? TelemetrySpy()
        return TestStore(
            initial: .launching(flight),
            reduce: Spaceship.Reducer(deps: .immediate(track: sink.record)).reduce
        )
    }

    // MARK: - Navigation is a state transition

    func test_selectingShip_routesToLaunchScreen() {
        var state = Spaceship.State(fleet: [atlas])

        let effect = makeReducer().reduce(&state, .shipSelected(atlas))

        XCTAssertEqual(state.path, [atlas.id])
        XCTAssertEqual(state.flight?.phase, .grounded)
        XCTAssertNotNil(effect)  // telemetry
    }

    func test_selectingShip_whileAlreadyOnLaunchScreen_isIgnored() {
        var state = Spaceship.State.launching(Spaceship.Flight(ship: atlas))

        let effect = makeReducer().reduce(&state, .shipSelected(cygnus))

        XCTAssertNil(effect)
        XCTAssertEqual(state.flight?.ship, atlas)
    }

    /// The bug this design exists to prevent.
    ///
    /// An earlier version kept the flight inside the route and a separate outcome alongside it, so
    /// re-entering built a fresh grounded flight while the fleet row still read "in orbit". Both screens
    /// now read one value, so they cannot drift.
    func test_reopeningAShip_showsThePhaseTheFleetShowed() {
        var state = Spaceship.State.launching(
            Spaceship.Flight(ship: atlas, phase: .inOrbit, altitude: 100)
        )
        let reducer = makeReducer()

        _ = reducer.reduce(&state, .pathChanged([]))
        XCTAssertEqual(state.flights[atlas.id]?.phase, .inOrbit)  // what the fleet row renders

        _ = reducer.reduce(&state, .shipSelected(atlas))

        XCTAssertEqual(state.flight?.phase, .inOrbit)
        XCTAssertEqual(state.flight?.altitude, 100)
    }

    func test_poppingTheStack_returnsToFleetAndCancelsTheFlight() {
        var state = Spaceship.State.launching(
            Spaceship.Flight(ship: atlas, phase: .countdown(secondsRemaining: 2))
        )

        let effect = makeReducer().reduce(&state, .pathChanged([]))

        XCTAssertEqual(state.path, [])
        XCTAssertNil(state.flight)
        XCTAssertNotNil(effect)
    }

    /// Leaving mid-flight resets, so no frozen phase is left behind.
    ///
    /// Without this the fleet row would claim a countdown that nothing is running.
    func test_poppingMidFlight_leavesTheShipGrounded() {
        var state = Spaceship.State.launching(
            Spaceship.Flight(ship: atlas, phase: .ascending, altitude: 60)
        )

        _ = makeReducer().reduce(&state, .pathChanged([]))

        XCTAssertEqual(state.flights[atlas.id]?.phase, .grounded)
        XCTAssertEqual(state.flights[atlas.id]?.altitude, 0)
    }

    func test_poppingFromATerminalPhase_keepsIt() {
        var state = Spaceship.State.launching(
            Spaceship.Flight(ship: atlas, phase: .inOrbit, altitude: 100)
        )

        _ = makeReducer().reduce(&state, .pathChanged([]))

        // Orbit is a result, not work in progress, so it survives leaving the screen.
        XCTAssertEqual(state.flights[atlas.id]?.phase, .inOrbit)
    }

    /// The case the `NavigationStack` path binding exists for.
    ///
    /// A back-swipe or the nav bar's back button never calls into the feature directly — it changes the
    /// stack, `store.binding` turns that into `.pathChanged`, and the reducer gets to cancel the countdown.
    /// Without that route a gesture would leave a stream ticking into a screen nobody is looking at.
    func test_aSwipeBackCancelsARunningCountdown() {
        var state = Spaceship.State.launching(
            Spaceship.Flight(ship: atlas, phase: .countdown(secondsRemaining: 2))
        )

        // Exactly what SwiftUI hands back when the user swipes: a shorter path.
        let effect = makeReducer().reduce(&state, .pathChanged([]))

        XCTAssertNotNil(effect)  // the cancellation
        XCTAssertEqual(state.flights[atlas.id]?.phase, .grounded)
    }

    func test_pathChanged_toTheSamePath_isIgnored() {
        var state = Spaceship.State.launching(Spaceship.Flight(ship: atlas))

        // SwiftUI can write the binding with an unchanged value; doing work for that would be waste.
        XCTAssertNil(makeReducer().reduce(&state, .pathChanged([atlas.id])))
    }

    // MARK: - Abort undoes the launch without navigating

    func test_abort_returnsTheShipToGroundedAndStaysOnTheStack() {
        var state = Spaceship.State.launching(
            Spaceship.Flight(ship: atlas, phase: .ascending, altitude: 60)
        )

        let effect = makeReducer().reduce(&state, .abortTapped)

        // An abort undoes the launch rather than becoming a state of its own.
        XCTAssertEqual(state.flight?.phase, .grounded)
        XCTAssertEqual(state.flight?.altitude, 0)
        XCTAssertEqual(state.path, [atlas.id])  // not a navigation change
        XCTAssertNotNil(effect)
    }

    // MARK: - Guards: actions arriving in a state that cannot handle them

    func test_launch_whileOnFleetScreen_isIgnored() {
        var state = Spaceship.State(fleet: [atlas])

        XCTAssertNil(makeReducer().reduce(&state, .launchTapped))
        XCTAssertEqual(state.path, [])
    }

    func test_launch_whileAlreadyFlying_isIgnored() {
        var state = Spaceship.State.launching(
            Spaceship.Flight(ship: atlas, phase: .ascending, altitude: 40)
        )

        XCTAssertNil(makeReducer().reduce(&state, .launchTapped))
        XCTAssertEqual(state.flight?.phase, .ascending)
    }

    /// A terminal phase is not a dead end: the guard is "not currently flying", not "grounded".
    func test_launchAgain_fromOrbit_isAllowed() {
        var state = Spaceship.State.launching(
            Spaceship.Flight(ship: atlas, phase: .inOrbit, altitude: 100)
        )

        let effect = makeReducer().reduce(&state, .launchTapped)

        XCTAssertNotNil(effect)
        XCTAssertEqual(state.flight?.phase, .runningChecks)
        XCTAssertEqual(state.flight?.altitude, 0)
    }

    func test_abort_whileGrounded_isIgnored() {
        var state = Spaceship.State.launching(Spaceship.Flight(ship: atlas))

        XCTAssertNil(makeReducer().reduce(&state, .abortTapped))
        XCTAssertEqual(state.flight?.phase, .grounded)
    }

    func test_fleetLoadsOnce() {
        var state = Spaceship.State(fleet: [atlas])

        // Already loaded, so re-appearing after a flight must not refetch.
        XCTAssertNil(makeReducer().reduce(&state, .fleetAppeared))
    }

    // MARK: - Async round-trips

    func test_fleetAppeared_loadsTheFleet() async {
        let store = TestStore(
            initial: Spaceship.State(),
            reduce: Spaceship.Reducer(deps: .immediate(fleet: [atlas, cygnus])).reduce
        )

        store.send(.fleetAppeared)
        XCTAssertTrue(store.state.isLoadingFleet)

        let received = await store.receive()

        XCTAssertEqual(received, .fleetLoaded([atlas, cygnus]))
        XCTAssertEqual(store.state.fleet, [atlas, cygnus])
        XCTAssertFalse(store.state.isLoadingFleet)
    }

    func test_shipInMaintenance_failsItsChecks() async {
        let store = makeLaunchStore(Spaceship.Flight(ship: cygnus))

        store.send(.launchTapped)
        let received = await store.receive()

        XCTAssertEqual(received, .checksCompleted(passed: false))
        XCTAssertEqual(store.state.flight?.phase, .checksFailed(reason: "Ship in maintenance"))
    }

    /// Walks a whole flight, one effect-produced action at a time.
    ///
    /// Every intermediate phase is asserted. Under a plain `Store` these would flash past in
    /// microseconds, so a test could only check the final state — and would still pass if the countdown
    /// never ticked at all.
    func test_fullFlight_reachesOrbit() async {
        let store = makeLaunchStore(Spaceship.Flight(ship: atlas))

        store.send(.launchTapped)
        XCTAssertEqual(store.state.flight?.phase, .runningChecks)

        await assertReceives(.checksCompleted(passed: true), on: store)
        XCTAssertEqual(store.state.flight?.phase, .countdown(secondsRemaining: 3))

        await assertReceives(.countdownTicked(secondsRemaining: 2), on: store)
        await assertReceives(.countdownTicked(secondsRemaining: 1), on: store)

        await assertReceives(.liftoff, on: store)
        XCTAssertEqual(store.state.flight?.phase, .ascending)

        for altitude in stride(from: 20, through: 100, by: 20) {
            await assertReceives(.altitudeChanged(altitude), on: store)
            XCTAssertEqual(store.state.flight?.altitude, altitude)
        }

        await assertReceives(.reachedOrbit, on: store)
        XCTAssertEqual(store.state.flight?.phase, .inOrbit)
        XCTAssertEqual(store.state.flights[atlas.id]?.phase, .inOrbit)
    }

    // MARK: - Fire-and-forget

    func test_launch_reportsTelemetryWithoutProducingAnAction() async {
        let spy = TelemetrySpy()
        let store = makeLaunchStore(Spaceship.Flight(ship: atlas), spy: spy)

        store.send(.launchTapped)
        await store.finish()

        // The telemetry effect produced no action; only the pre-flight check's did.
        XCTAssertEqual(spy.entries, ["Launch requested: Atlas"])
        XCTAssertEqual(store.unconsumedActionCount, 1)
    }

    // MARK: - Helpers

    private func assertReceives(
        _ expected: Spaceship.Action,
        on store: TestStore<Spaceship.State, Spaceship.Action>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let received = await store.receive()
        XCTAssertEqual(received, expected, file: file, line: line)
    }
}
