import CoreArchitecture
import Foundation

/// Namespace for the coordination feature: which screen is showing, and what each launch came to.
///
/// The third store in the demo, and the one that exists for a reason worth noticing. `Fleet` and `Launch`
/// each own a screen's own state; neither can own *navigation between them*, and neither can own a fact the
/// other produces. Both of those belong to whoever coordinates — here, `SpaceshipFlow`.
///
/// In a UIKit app this state is what a `Coordinator` would hold. Keeping it in a store instead means the
/// transitions are reducer-tested like any others.
public enum Flow {}

extension Flow {

    /// Everything the coordination layer owns.
    public struct State: Equatable {

        /// The navigation stack: empty is the fleet, one ship is that ship's launch screen.
        ///
        /// It carries whole ships rather than ids so the flow can build a launch screen without reaching
        /// into the fleet's state, which it does not own.
        public var path: [Spaceship.Ship]

        /// What each ship's last launch came to.
        ///
        /// Written only by `flightFinished`. This is the cross-feature fact: `Launch` produces it and
        /// `Fleet` renders it, so neither can be its home.
        public var results: [Spaceship.Ship.ID: Spaceship.Phase]

        /// Creates a coordination state, defaulting to the fleet screen with nothing flown yet.
        ///
        /// - Parameters:
        ///   - path: The navigation stack to start on.
        ///   - results: Results already recorded.
        public init(
            path: [Spaceship.Ship] = [],
            results: [Spaceship.Ship.ID: Spaceship.Phase] = [:]
        ) {
            self.path = path
            self.results = results
        }
    }

    /// Every event the coordination layer can receive.
    ///
    /// All three arrive from outside itself: one from a screen's output, one from the navigation container,
    /// one from another feature. It has no effects of its own beyond telemetry.
    public enum Action: Equatable {

        /// The fleet screen reported a selection. It does not know this pushes anything.
        case shipSelected(Spaceship.Ship)
        /// The navigation stack changed, by a push, the back button, or a back-swipe.
        case pathChanged([Spaceship.Ship])
        /// A launch reported its result.
        case flightFinished(shipID: Spaceship.Ship.ID, phase: Spaceship.Phase)
    }

    /// The collaborators that keep `Flow.Reducer` pure.
    public struct Dependencies {

        /// Sends a line of telemetry to ground control.
        public var track: @MainActor (String) -> Void

        /// Creates a dependency set.
        ///
        /// - Parameter track: Receives a line of telemetry.
        public init(track: @escaping @MainActor (String) -> Void) {
            self.track = track
        }
    }
}
