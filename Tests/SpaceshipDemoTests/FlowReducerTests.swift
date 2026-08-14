import CoreArchitecture
import Testing

@testable import SpaceshipDemo

/// The coordination feature, tested on its own.
///
/// This is the store that exists so navigation and cross-feature results stay reducer-tested. In a UIKit app
/// the same state would sit in a `Coordinator`, where none of these assertions would be possible without a
/// window.
@MainActor
struct FlowReducerTests {

    private let atlas = Spaceship.Ship(id: "atlas", name: "Atlas", readiness: .ready)
    private let cygnus = Spaceship.Ship(id: "cygnus", name: "Cygnus", readiness: .inMaintenance)

    private func makeReducer() -> Flow.Reducer {
        Flow.Reducer(dependencies: .init(track: { _ in }))
    }

    // MARK: - Navigation

    /// The fleet screen reports a selection; deciding it means a push happens here.
    @Test
    func selectingShipPushesIt() {
        var state = Flow.State()

        let effect = makeReducer().reduce(&state, .shipSelected(atlas))

        #expect(state.path == [atlas])
        #expect(effect != nil)  // telemetry
    }

    @Test
    func selectingShipWhileAlreadyPushedIsIgnored() {
        var state = Flow.State(path: [atlas])

        #expect(makeReducer().reduce(&state, .shipSelected(cygnus)) == nil)
        #expect(state.path == [atlas])
    }

    /// Popping needs no cleanup, which is the point of a store per screen.
    ///
    /// The launch store belongs to the pushed screen, so popping releases it and `Store.deinit` cancels
    /// whatever it had running. This reducer has nothing to cancel and returns no effect.
    @Test
    func poppingTheStackNeedsNoCleanup() {
        var state = Flow.State(path: [atlas])

        let effect = makeReducer().reduce(&state, .pathChanged([]))

        #expect(state.path == [])
        #expect(effect == nil)
    }

    /// A back-swipe is handled exactly like any other action.
    ///
    /// SwiftUI writes the shorter path through `store.binding`, which arrives here as `.pathChanged`. Routing
    /// it through a reducer is what makes a system gesture testable at all.
    @Test
    func aSwipeBackPopsTheStack() {
        var state = Flow.State(path: [atlas])

        _ = makeReducer().reduce(&state, .pathChanged([]))

        #expect(state.path.isEmpty)
    }

    @Test
    func pathChangedToTheSamePathIsIgnored() {
        var state = Flow.State(path: [atlas])

        // SwiftUI can write the binding with an unchanged value; doing work for that would be waste.
        #expect(makeReducer().reduce(&state, .pathChanged([atlas])) == nil)
    }

    // MARK: - Cross-feature results

    /// The flow learns what happened only by being told.
    ///
    /// `Launch` reports through a dependency, so the result reaches here as an ordinary action — exactly as a
    /// network response would.
    @Test
    func aReportedResultIsRecorded() {
        var state = Flow.State()

        _ = makeReducer().reduce(&state, .flightFinished(shipID: atlas.id, phase: .inOrbit))

        #expect(state.results[atlas.id] == .inOrbit)
    }

    @Test
    func aLaterResultReplacesTheEarlierOne() {
        var state = Flow.State(results: [atlas.id: .inOrbit])

        _ = makeReducer().reduce(
            &state,
            .flightFinished(shipID: atlas.id, phase: .checksFailed(reason: "x"))
        )

        #expect(state.results[atlas.id] == .checksFailed(reason: "x"))
    }

    @Test
    func selectingShipReportsTelemetry() async {
        let spy = Spy()
        let store = TestStore(
            initial: Flow.State(),
            reduce: Flow.Reducer(dependencies: .init(track: spy.track)).reduce
        )

        store.send(.shipSelected(atlas))
        await store.finish()

        #expect(spy.telemetry == ["Selected Atlas"])
        #expect(store.unconsumedActionCount == 0)
    }
}
