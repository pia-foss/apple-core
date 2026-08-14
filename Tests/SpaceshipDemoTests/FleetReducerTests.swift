import CoreArchitecture
import Testing

@testable import SpaceshipDemo

/// The fleet feature, tested on its own.
///
/// Two actions and one dependency, so there are only two things to assert. Notice what these tests cannot
/// mention: no navigation, no results, no countdown. None of that is the fleet's, so none of it is in scope
/// here — which is the clearest argument for a store per screen.
@MainActor
struct FleetReducerTests {

    private let atlas = Spaceship.Ship(id: "atlas", name: "Atlas", readiness: .ready)
    private let cygnus = Spaceship.Ship(id: "cygnus", name: "Cygnus", readiness: .inMaintenance)

    private func makeReducer() -> Fleet.Reducer {
        Fleet.Reducer(dependencies: .immediate())
    }

    @Test
    func appearedLoadsTheShips() async {
        let store = TestStore(
            initial: Fleet.State(),
            reduce: Fleet.Reducer(dependencies: .immediate(ships: [atlas, cygnus])).reduce
        )

        store.send(.appeared)
        #expect(store.state.isLoading)

        let received = await store.receive()

        #expect(received == .shipsLoaded([atlas, cygnus]))
        #expect(store.state.ships == [atlas, cygnus])
        #expect(store.state.isLoading == false)
    }

    /// The screen's store outlives a push, so coming back re-triggers `appeared`.
    ///
    /// Refetching then would throw away a list the pilot is already looking at.
    @Test
    func appearedAfterLoadingDoesNotRefetch() {
        var state = Fleet.State(ships: [atlas])

        #expect(makeReducer().reduce(&state, .appeared) == nil)
    }

    @Test
    func appearedWhileLoadingDoesNotRefetch() {
        var state = Fleet.State(isLoading: true)

        #expect(makeReducer().reduce(&state, .appeared) == nil)
    }

    @Test
    func shipsLoadedClearsTheLoadingFlag() {
        var state = Fleet.State(isLoading: true)

        _ = makeReducer().reduce(&state, .shipsLoaded([atlas]))

        #expect(state.ships == [atlas])
        #expect(state.isLoading == false)
    }
}
