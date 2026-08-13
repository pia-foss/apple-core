import CoreArchitecture
import Foundation

extension Fleet {

    /// The only place `Fleet.State` mutates.
    public struct Reducer {

        /// The state this reducer moves.
        public typealias State = Fleet.State

        /// The events this reducer accepts.
        public typealias Action = Fleet.Action

        /// The injected collaborators.
        public let dependencies: Dependencies

        /// Creates a reducer bound to `dependencies`.
        ///
        /// - Parameter dependencies: The collaborators every effect runs through.
        public init(dependencies: Dependencies) {
            self.dependencies = dependencies
        }

        /// Applies `action` to `state` and returns any work that should follow.
        ///
        /// - Parameters:
        ///   - state: The state to mutate in place.
        ///   - action: The event to apply.
        /// - Returns: Work to perform, or `nil` when the action needs none.
        public func reduce(_ state: inout State, _ action: Action) -> Effect<Action>? {
            switch action {
            case .appeared: return load(in: &state)
            case .shipsLoaded(let ships): return show(ships, in: &state)
            }
        }
    }
}

extension Fleet.Reducer {

    /// Fetches the ships, unless they are already loaded or loading.
    ///
    /// The screen's store outlives a push, so coming back re-triggers `appeared` — and refetching then would
    /// throw away a list the pilot is already looking at.
    private func load(in state: inout State) -> Effect<Action>? {
        guard state.ships.isEmpty, !state.isLoading else { return nil }
        state.isLoading = true
        return .task { [dependencies] in .shipsLoaded(await dependencies.fleetRepository.all()) }
    }

    private func show(_ ships: [Spaceship.Ship], in state: inout State) -> Effect<Action>? {
        state.isLoading = false
        state.ships = ships
        return nil
    }
}
