import CoreArchitecture
import XCTest

@testable import SpaceshipDemo

/// The coordination feature, tested on its own.
///
/// This is the store that exists so navigation and cross-feature results stay reducer-tested. In a UIKit app
/// the same state would sit in a `Coordinator`, where none of these assertions would be possible without a
/// window.
@MainActor
final class FlowReducerTests: XCTestCase {

    private let atlas = Spaceship.Ship(id: "atlas", name: "Atlas", readiness: .ready)
    private let cygnus = Spaceship.Ship(id: "cygnus", name: "Cygnus", readiness: .inMaintenance)

    private func makeReducer() -> Flow.Reducer {
        Flow.Reducer(dependencies: .init(track: { _ in }))
    }

    // MARK: - Navigation

    /// The fleet screen reports a selection; deciding it means a push happens here.
    func test_selectingShip_pushesIt() {
        var state = Flow.State()

        let effect = makeReducer().reduce(&state, .shipSelected(atlas))

        XCTAssertEqual(state.path, [atlas])
        XCTAssertNotNil(effect)  // telemetry
    }

    func test_selectingShip_whileAlreadyPushed_isIgnored() {
        var state = Flow.State(path: [atlas])

        XCTAssertNil(makeReducer().reduce(&state, .shipSelected(cygnus)))
        XCTAssertEqual(state.path, [atlas])
    }

    /// Popping needs no cleanup, which is the point of a store per screen.
    ///
    /// The launch store belongs to the pushed screen, so popping releases it and `Store.deinit` cancels
    /// whatever it had running. This reducer has nothing to cancel and returns no effect.
    func test_poppingTheStack_needsNoCleanup() {
        var state = Flow.State(path: [atlas])

        let effect = makeReducer().reduce(&state, .pathChanged([]))

        XCTAssertEqual(state.path, [])
        XCTAssertNil(effect)
    }

    /// A back-swipe is handled exactly like any other action.
    ///
    /// SwiftUI writes the shorter path through `store.binding`, which arrives here as `.pathChanged`. Routing
    /// it through a reducer is what makes a system gesture testable at all.
    func test_aSwipeBackPopsTheStack() {
        var state = Flow.State(path: [atlas])

        _ = makeReducer().reduce(&state, .pathChanged([]))

        XCTAssertTrue(state.path.isEmpty)
    }

    func test_pathChanged_toTheSamePath_isIgnored() {
        var state = Flow.State(path: [atlas])

        // SwiftUI can write the binding with an unchanged value; doing work for that would be waste.
        XCTAssertNil(makeReducer().reduce(&state, .pathChanged([atlas])))
    }

    // MARK: - Cross-feature results

    /// The flow learns what happened only by being told.
    ///
    /// `Launch` reports through a dependency, so the result reaches here as an ordinary action — exactly as a
    /// network response would.
    func test_aReportedResultIsRecorded() {
        var state = Flow.State()

        _ = makeReducer().reduce(&state, .flightFinished(shipID: atlas.id, phase: .inOrbit))

        XCTAssertEqual(state.results[atlas.id], .inOrbit)
    }

    func test_aLaterResultReplacesTheEarlierOne() {
        var state = Flow.State(results: [atlas.id: .inOrbit])

        _ = makeReducer().reduce(
            &state,
            .flightFinished(shipID: atlas.id, phase: .checksFailed(reason: "x"))
        )

        XCTAssertEqual(state.results[atlas.id], .checksFailed(reason: "x"))
    }

    func test_selectingShip_reportsTelemetry() async {
        let spy = Spy()
        let store = TestStore(
            initial: Flow.State(),
            reduce: Flow.Reducer(dependencies: .init(track: spy.track)).reduce
        )

        store.send(.shipSelected(atlas))
        await store.finish()

        XCTAssertEqual(spy.telemetry, ["Selected Atlas"])
        XCTAssertEqual(store.unconsumedActionCount, 0)
    }
}
