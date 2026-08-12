import CoreArchitecture
import XCTest

@testable import SpaceshipDemo

/// Shows both ways to test a reducer.
///
/// Claims about a synchronous mutation, or about *whether* an effect was returned, go straight to the
/// reducer — it is a pure function, so no runtime is needed. Claims about an async round-trip go
/// through `TestStore`. The runtime's own cancellation semantics are covered by the library's tests,
/// not re-proven here.
@MainActor
final class SpaceshipReducerTests: XCTestCase {

    /// Builds a test store on immediate dependencies, so a whole flight runs without waiting.
    ///
    /// `log` is created here rather than defaulted, because a default argument is evaluated in a
    /// nonisolated context and `TelemetryLog` is main-actor isolated.
    private func makeStore(
        checksPass: Bool = true,
        log: TelemetryLog? = nil
    ) -> TestStore<Spaceship.State, Spaceship.Action> {
        let sink = log ?? TelemetryLog()
        return TestStore(
            initial: Spaceship.State(),
            reduce: Spaceship.Reducer(
                deps: .immediate(checksPass: checksPass, track: sink.record)
            ).reduce
        )
    }

    // MARK: - Pure reducer

    func test_launchTapped_startsChecksAndReturnsWork() {
        let reducer = Spaceship.Reducer(deps: .immediate())
        var state = Spaceship.State()

        let effect = reducer.reduce(&state, .launchTapped)

        XCTAssertEqual(state.phase, .runningChecks)
        XCTAssertNotNil(effect)
    }

    func test_launchTapped_whileNotGrounded_isIgnored() {
        let reducer = Spaceship.Reducer(deps: .immediate())
        var state = Spaceship.State(phase: .ascending, altitude: 40)

        let effect = reducer.reduce(&state, .launchTapped)

        XCTAssertNil(effect)
        XCTAssertEqual(state.phase, .ascending)
    }

    func test_abort_stopsTheFlightAndReturnsCancellation() {
        let reducer = Spaceship.Reducer(deps: .immediate())
        var state = Spaceship.State(phase: .countdown(secondsRemaining: 2))

        let effect = reducer.reduce(&state, .abortTapped)

        XCTAssertEqual(state.phase, .aborted)
        XCTAssertEqual(state.altitude, 0)
        XCTAssertNotNil(effect)
    }

    func test_abort_whenGrounded_isIgnored() {
        let reducer = Spaceship.Reducer(deps: .immediate())
        var state = Spaceship.State()

        XCTAssertNil(reducer.reduce(&state, .abortTapped))
        XCTAssertEqual(state.phase, .grounded)
    }

    // MARK: - Async round-trips

    func test_failedChecks_reportTheReason() async {
        let store = makeStore(checksPass: false)

        store.send(.launchTapped)
        let received = await store.receive()

        XCTAssertEqual(received, .checksCompleted(passed: false))
        XCTAssertEqual(store.state.phase, .checksFailed(reason: "Fuel pressure low"))
    }

    func test_passedChecks_beginTheCountdown() async {
        let store = makeStore()

        store.send(.launchTapped)
        let received = await store.receive()

        XCTAssertEqual(received, .checksCompleted(passed: true))
        XCTAssertEqual(store.state.phase, .countdown(secondsRemaining: 3))
    }

    /// Walks a whole flight, one effect-produced action at a time.
    ///
    /// Reads as the flight reads, which is the payoff of queuing effect output rather than applying
    /// it: every intermediate state is observable instead of raced past.
    func test_fullFlight_reachesOrbit() async {
        let store = makeStore()

        store.send(.launchTapped)
        XCTAssertEqual(store.state.phase, .runningChecks)

        await assertReceives(.checksCompleted(passed: true), on: store)
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

    // MARK: - Fire-and-forget

    func test_launch_reportsTelemetryWithoutProducingAnAction() async {
        let log = TelemetryLog()
        let store = makeStore(log: log)

        store.send(.launchTapped)
        await store.finish()

        // The telemetry effect produced no action; only the pre-flight check's did.
        XCTAssertEqual(log.entries, ["Launch requested"])
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
