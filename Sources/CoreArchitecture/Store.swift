import Combine
import Foundation

/// The unidirectional-MVI store from ADR 0010: holds feature `State`, is the single mutation path
/// via `send`, runs the `Effect`s a reducer returns, and feeds their actions back in.
///
/// *State flows down, actions flow up.* Views own the store via `@StateObject`, read `store.state`
/// (read-only), and dispatch with `store.send(_:)`. The reducer passed in is pure — it captures its
/// `Dependencies` at construction, and the store never sees them.
///
/// ```swift
/// struct ItemView: View {
///     @StateObject var store = Store(
///         initial: ItemState(),
///         reduce: ItemReducer(deps: .live).reduce
///     )
///
///     var body: some View {
///         List(store.state.items) { … }
///             .task { store.send(.onAppear) }
///     }
/// }
/// ```
///
/// Effects given an `id` are tracked and cancellable — see `Effect` for the cancellation rules.
/// Anything still in flight is cancelled when the store is released, so a long-lived `.stream`
/// effect does not outlive the screen that started it.
///
/// Deployment-target note (ADR 0010): this uses `ObservableObject` + `@Published` because
/// `@Observable` requires iOS 17 and the app targets iOS 15. When the target moves to iOS 17 the
/// swap to `@Observable` is localized here — views already read `store.state` without knowing the
/// mechanism.
@MainActor
public final class Store<State, Action>: ObservableObject {

    @Published public private(set) var state: State

    private let _reduce: (inout State, Action) -> Effect<Action>?

    /// A `let` of a `Sendable` type, which is what lets `deinit` reach it without isolation.
    private let tasks = EffectRuntime.Tasks()

    public init(initial: State, reduce: @escaping (inout State, Action) -> Effect<Action>?) {
        self.state = initial
        self._reduce = reduce
    }

    deinit {
        // Without this, a `.stream` effect observing the VPN engine or running a reconnect loop
        // keeps running after its screen is gone. Effect sinks capture the store weakly, so the
        // work would be invisible as well as unbounded.
        tasks.cancelAll()
    }

    /// The only way to mutate state. Runs the reducer synchronously, then any returned effect off
    /// the reduce cycle, feeding the actions it produces back through `send`.
    public func send(_ action: Action) {
        guard let effect = _reduce(&state, action) else { return }
        EffectRuntime.run(effect, tasks: tasks) { [weak self] action in
            self?.send(action)
        }
    }

    /// Cancels every in-flight effect. Rarely needed — effects are normally cancelled by id from a
    /// reducer, and teardown is automatic — but useful when a host must stop a feature's work
    /// without releasing the store.
    public func cancelAllEffects() {
        tasks.cancelAll()
    }
}
