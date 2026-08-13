import CoreArchitecture
import XCTest

@testable import SpaceshipDemo

/// The fleet feature, tested on its own.
///
/// Two actions and one dependency, so there are only two things to assert. Notice what these tests cannot
/// mention: no navigation, no results, no countdown. None of that is the fleet's, so none of it is in scope
/// here — which is the clearest argument for a store per screen.
@MainActor
final class FleetReducerTests: XCTestCase {

    private let atlas = Spaceship.Ship(id: "atlas", name: "Atlas", readiness: .ready)
    private let cygnus = Spaceship.Ship(id: "cygnus", name: "Cygnus", readiness: .inMaintenance)

    private func makeReducer() -> Fleet.Reducer {
        Fleet.Reducer(dependencies: .immediate())
    }

    func test_appeared_loadsTheShips() async {
        let store = TestStore(
            initial: Fleet.State(),
            reduce: Fleet.Reducer(dependencies: .immediate(ships: [atlas, cygnus])).reduce
        )

        store.send(.appeared)
        XCTAssertTrue(store.state.isLoading)

        let received = await store.receive()

        XCTAssertEqual(received, .shipsLoaded([atlas, cygnus]))
        XCTAssertEqual(store.state.ships, [atlas, cygnus])
        XCTAssertFalse(store.state.isLoading)
    }

    /// The screen's store outlives a push, so coming back re-triggers `appeared`.
    ///
    /// Refetching then would throw away a list the pilot is already looking at.
    func test_appeared_afterLoading_doesNotRefetch() {
        var state = Fleet.State(ships: [atlas])

        XCTAssertNil(makeReducer().reduce(&state, .appeared))
    }

    func test_appeared_whileLoading_doesNotRefetch() {
        var state = Fleet.State(isLoading: true)

        XCTAssertNil(makeReducer().reduce(&state, .appeared))
    }

    func test_shipsLoaded_clearsTheLoadingFlag() {
        var state = Fleet.State(isLoading: true)

        _ = makeReducer().reduce(&state, .shipsLoaded([atlas]))

        XCTAssertEqual(state.ships, [atlas])
        XCTAssertFalse(state.isLoading)
    }
}
