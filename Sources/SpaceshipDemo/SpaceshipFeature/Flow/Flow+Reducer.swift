import CoreArchitecture
import Foundation

extension Flow {

    /// The only place `Flow.State` mutates.
    ///
    /// Three transitions, no cancellation, no loading. Coordination turns out to be small once each screen
    /// owns its own state — which is the argument for giving it a store rather than leaving it as view state.
    public struct Reducer {

        /// The state this reducer moves.
        public typealias State = Flow.State

        /// The events this reducer accepts.
        public typealias Action = Flow.Action

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
            case .shipSelected(let ship): return push(ship, in: &state)
            case .pathChanged(let path): return navigate(to: path, in: &state)
            case .flightFinished(let id, let phase): return record(phase, for: id, in: &state)
            }
        }
    }
}

extension Flow.Reducer {

    /// Pushes the launch screen for `ship`.
    ///
    /// The fleet screen reported a selection; deciding that a selection means a push is this reducer's job
    /// and nowhere else's.
    private func push(_ ship: Spaceship.Ship, in state: inout State) -> Effect<Action>? {
        guard state.path.isEmpty else { return nil }
        state.path = [ship]
        return .fireAndForget { [dependencies] in dependencies.track("Selected \(ship.name)") }
    }

    /// Moves the navigation stack to `path`.
    ///
    /// No cleanup: the launch store belongs to the pushed screen, so popping releases it and `Store.deinit`
    /// cancels whatever it had running. That is what a store per screen buys.
    private func navigate(to path: [Spaceship.Ship], in state: inout State) -> Effect<Action>? {
        guard path != state.path else { return nil }
        state.path = path
        return nil
    }

    /// Records what a launch came to, so the fleet screen can render it.
    private func record(
        _ phase: Spaceship.Phase,
        for shipID: Spaceship.Ship.ID,
        in state: inout State
    ) -> Effect<Action>? {
        state.results[shipID] = phase
        return nil
    }
}
