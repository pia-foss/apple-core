import Combine
import Foundation

/// An observable container for one feature's state, and the only path through which it mutates.
///
/// Views own the store, read `state`, and dispatch with `send(_:)`. The reducer it runs is pure: it
/// captures its dependencies at construction, and the store never sees them. Effects still in flight
/// are cancelled when the store is released.
///
/// - Note: Uses `ObservableObject` rather than `@Observable` to support iOS 15. Views read `state`
///   without knowing which mechanism is underneath, so the swap stays local to this type.
@MainActor
public final class Store<State, Action>: ObservableObject {

    /// The feature's current state.
    ///
    /// Read-only to callers; mutate it by sending an action.
    @Published public private(set) var state: State

    private let _reduce: (inout State, Action) -> Effect<Action>?

    /// A `let` of a `Sendable` type, which is what lets `deinit` reach it without isolation.
    private let tasks = EffectRuntime.Tasks()

    /// Creates a store seeded with `initial`, reducing actions with `reduce`.
    ///
    /// - Parameters:
    ///   - initial: The state the feature starts in.
    ///   - reduce: Mutates state for an action and optionally returns work to perform. Must be pure.
    public init(initial: State, reduce: @escaping (inout State, Action) -> Effect<Action>?) {
        self.state = initial
        self._reduce = reduce
    }

    deinit {
        // A long-lived effect would otherwise outlive the store, and its sink holds `self` weakly, so
        // the work would be invisible as well as unbounded.
        tasks.cancelAll()
    }

    /// Dispatches `action` through the reducer, then runs any effect it returns.
    ///
    /// The only way to mutate `state`.
    public func send(_ action: Action) {
        guard let effect = _reduce(&state, action) else { return }
        EffectRuntime.run(effect, tasks: tasks) { [weak self] action in
            self?.send(action)
        }
    }

    /// Cancels every in-flight effect.
    ///
    /// Rarely needed, since effects are normally cancelled by `id` from a reducer and teardown is
    /// automatic. Useful when a host must stop a feature's work without releasing the store.
    public func cancelAllEffects() {
        tasks.cancelAll()
    }
}
