import Foundation

/// A description of asynchronous work returned by a reducer.
///
/// A reducer stays pure by returning an effect rather than performing I/O itself; the runtime runs it
/// off the reduce cycle and feeds the actions it produces back in. Build effects with `task`,
/// `fireAndForget`, `stream`, `merge` and `cancel`; returning `nil` from a reducer means "no effect".
///
/// - Important: Effects sharing an `id` run one at a time — starting one cancels whatever is already
///   in flight under that `id`. Effects meant to run concurrently need distinct ids, or none.
public struct Effect<Action> {

    /// The main-actor-isolated sink an effect uses to feed actions back into the runtime.
    ///
    /// Effect bodies are isolated too, so calling it needs no `await`.
    public typealias Send = @MainActor (Action) -> Void

    /// The shape the runtime interprets.
    ///
    /// Internal so the runtime can gain cases without breaking the public API; reducers describe work
    /// with the factories instead.
    enum Operation {
        /// A non-`nil` `id` opts the work into cancellation.
        case run(id: AnyHashable?, work: @MainActor (Send) async -> Void)
        case cancel(id: AnyHashable)
        case merge([Effect])
    }

    let operation: Operation

    init(operation: Operation) {
        self.operation = operation
    }

    /// Wraps one-shot work that produces a single follow-up action.
    ///
    /// The common case: a fetch, a submit, a purchase.
    ///
    /// - Parameters:
    ///   - id: Opts the work into cancellation. Omit when it never needs cancelling.
    ///   - work: Returns the action to dispatch, or `nil` to produce none.
    /// - Returns: An effect that dispatches `work`'s action, if it produces one.
    public static func task(
        id: AnyHashable? = nil,
        _ work: @escaping @MainActor () async -> Action?
    ) -> Effect {
        Effect(
            operation: .run(id: id) { send in
                if let action = await work() {
                    send(action)
                }
            }
        )
    }

    /// Wraps work that produces no action, such as analytics, logging or a persist.
    ///
    /// How a reducer reaches a dependency without performing I/O itself: calling one inline would
    /// cost the reducer its purity.
    ///
    /// - Parameters:
    ///   - id: Opts the work into cancellation. Omit when it never needs cancelling.
    ///   - work: Performs the side effect.
    /// - Returns: An effect that performs `work` and produces no action.
    public static func fireAndForget(
        id: AnyHashable? = nil,
        _ work: @escaping @MainActor () async -> Void
    ) -> Effect {
        Effect(operation: .run(id: id) { _ in await work() })
    }

    /// Wraps long-lived work that emits actions over time, such as engine observation, timers or
    /// retry loops.
    ///
    /// `task` cannot express this, because it emits at most one action.
    ///
    /// - Parameters:
    ///   - id: Required rather than defaulted: a stream nobody can cancel runs until the store is
    ///     torn down.
    ///   - work: Emits actions through the sink it is given, until cancelled.
    /// - Returns: An effect that runs `work` until it completes or is cancelled.
    public static func stream(
        id: AnyHashable,
        _ work: @escaping @MainActor (Send) async -> Void
    ) -> Effect {
        Effect(operation: .run(id: id, work: work))
    }

    /// Starts several effects together, each cancellable independently by its own `id`.
    public static func merge(_ effects: Effect...) -> Effect {
        merge(effects)
    }

    /// Starts several effects together, each cancellable independently by its own `id`.
    public static func merge(_ effects: [Effect]) -> Effect {
        Effect(operation: .merge(effects))
    }

    /// Cancels the in-flight effect tracked under `id`.
    ///
    /// A no-op when nothing is running under `id`, so a reducer can cancel defensively.
    public static func cancel(id: AnyHashable) -> Effect {
        Effect(operation: .cancel(id: id))
    }
}
