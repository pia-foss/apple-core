import Foundation

extension Spaceship {

    /// Everything the feature renders, and the single source of truth for both screens.
    public struct State: Equatable {

        /// The ships available to launch.
        public var fleet: [Ship]

        /// Whether the fleet is still loading.
        public var isLoadingFleet: Bool

        /// The navigation stack: empty is the fleet screen, one id is that ship's launch screen.
        ///
        /// Navigation is state, which is what makes it unit-testable — a reducer test asserts "selecting a
        /// ship pushes the launch screen" with no view, window, or navigation controller. It is an array
        /// rather than an enum so a `NavigationStack` can bind straight to it, which also means the
        /// system back button and the swipe-back gesture arrive here as ordinary actions.
        public var path: [Ship.ID]

        /// One flight per ship the pilot has opened.
        ///
        /// Both screens read a ship's phase from here, which is the point: an earlier design kept the
        /// flight inside the route and a separate outcome alongside it, so the fleet list and the launch
        /// screen held two representations of one fact and drifted apart. One value cannot disagree with
        /// itself.
        public var flights: [Ship.ID: Flight]

        /// Creates a state, defaulting to an empty fleet screen.
        ///
        /// - Parameters:
        ///   - fleet: The ships available to launch.
        ///   - isLoadingFleet: Whether the fleet is still loading.
        ///   - path: The navigation stack to start on.
        ///   - flights: Any flights already under way or finished.
        public init(
            fleet: [Ship] = [],
            isLoadingFleet: Bool = false,
            path: [Ship.ID] = [],
            flights: [Ship.ID: Flight] = [:]
        ) {
            self.fleet = fleet
            self.isLoadingFleet = isLoadingFleet
            self.path = path
            self.flights = flights
        }
    }
}

extension Spaceship.State {

    /// The flight the top of the stack is showing, or `nil` on the fleet screen.
    ///
    /// Reading and writing through here keeps the reducer legible — `state.flight?.phase = .ascending`
    /// instead of reaching through the path into the dictionary by hand.
    public var flight: Spaceship.Flight? {
        get {
            guard let id = path.last else { return nil }
            return flights[id]
        }
        set {
            guard let id = path.last, let newValue else { return }
            flights[id] = newValue
        }
    }

    /// Creates a state already showing the launch screen for `flight`.
    ///
    /// A convenience for tests and previews, which otherwise have to keep `path` and `flights` in step by
    /// hand.
    ///
    /// - Parameter flight: The flight to open on.
    /// - Returns: A state pushed to `flight`, with it registered in `flights`.
    public static func launching(_ flight: Spaceship.Flight) -> Self {
        Self(
            fleet: [flight.ship],
            path: [flight.ship.id],
            flights: [flight.ship.id: flight]
        )
    }
}
