import Foundation

/// A description of asynchronous work returned by a reducer.
///
/// The reducer stays pure by never performing I/O itself: it returns an `Effect`, and the runtime
/// (`Store` in the app, `TestStore` in tests) runs it off the reduce cycle, feeding any actions it
/// produces back through `send`. This is the seam ADR 0010 relies on — that ADR keeps all impurity
/// (network, VPN engine, persistence, clock) behind injected `Dependencies`, invoked only via
/// effects, and this type is what "only via effects" means in code.
///
/// Build effects with the factories below — `task`, `fireAndForget`, `stream`, `merge`, `cancel`.
/// Returning `nil` from `reduce` means "no effect".
///
/// ## Isolation
///
/// Effect bodies are `@MainActor`. This is deliberate: a `Dependencies` closure in this codebase
/// usually wraps an existing singleton (`VPNManager.shared`, `AnalyticsManager.shared`) that is not
/// thread-safe, and a non-isolated body would call it from the global executor. Suspending on
/// `await deps.fetch()` still releases the main thread — the underlying network or engine work runs
/// wherever its implementation runs — so what stays on the main actor is only the glue. An effect
/// that genuinely needs to burn CPU should hop off explicitly rather than assume it may.
///
/// ## Cancellation
///
/// An effect given an `id` is tracked by the runtime and can be torn down with `.cancel(id:)`.
/// **The same `id` means one at a time: starting a new effect under an `id` cancels whatever was
/// already in flight under it.** That is the semantic debouncing, reconnect timers, and
/// re-subscription all want. Two effects that must genuinely run concurrently need distinct ids (or
/// none at all).
///
/// Cancellation is cooperative, as everywhere in Swift concurrency: the runtime cancels the `Task`,
/// and the effect body observes it by awaiting something that throws on cancellation, checking
/// `Task.isCancelled`, or iterating an `AsyncSequence` that ends when cancelled.
public struct Effect<Action> {

    /// The sink an effect uses to feed actions back into the runtime.
    ///
    /// Main-actor isolated, because state mutation is. Effect bodies are isolated too, so calling it
    /// needs no `await`.
    public typealias Send = @MainActor (Action) -> Void

    /// The shape `EffectRuntime` interprets.
    ///
    /// Internal on purpose: feature code describes work with the factories and never has reason to
    /// match on this, so keeping it out of the public API leaves the runtime free to grow new cases
    /// without that being a breaking change.
    enum Operation {
        /// Async work emitting zero or more actions through its sink. A non-`nil` `id` opts the
        /// work into cancellation.
        case run(id: AnyHashable?, work: @MainActor (Send) async -> Void)
        /// Cancels the in-flight effect tracked under `id`, if there is one.
        case cancel(id: AnyHashable)
        /// Starts several effects together. Each retains its own `id`.
        case merge([Effect])
    }

    let operation: Operation

    init(operation: Operation) {
        self.operation = operation
    }

    /// One-shot work producing a single follow-up action, or `nil` to produce none.
    ///
    /// The common case — a fetch, a submit, a purchase:
    /// ```swift
    /// return .task { [deps] in .itemsLoaded((try? await deps.fetchItems()) ?? []) }
    /// ```
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

    /// Work that produces no action — analytics, logging, a fire-and-forget persist.
    ///
    /// This is how a reducer reaches a dependency without giving up purity. ADR 0010 requires
    /// `reduce` to be a pure function with no I/O, and calling `deps.track(…)` inline breaks that;
    /// returning the call as an effect keeps the reducer deterministic in what it produces:
    /// ```swift
    /// state.phase = .declined
    /// return .fireAndForget { [deps] in deps.track(.declined) }
    /// ```
    public static func fireAndForget(
        id: AnyHashable? = nil,
        _ work: @escaping @MainActor () async -> Void
    ) -> Effect {
        Effect(operation: .run(id: id) { _ in await work() })
    }

    /// Long-lived work emitting actions over time — engine observation, timers, retry loops.
    ///
    /// The shape a state machine driven by an external source needs; `task` cannot express it,
    /// because it emits at most one action. ADR 0010 scopes MVI to features where multiple async
    /// inputs converge — engine, API and timers — and this is how those inputs arrive:
    /// ```swift
    /// return .stream(id: EffectID.vpnStatus) { [deps] send in
    ///     for await status in deps.vpnStatusUpdates() {
    ///         send(.statusChanged(status))
    ///     }
    /// }
    /// ```
    ///
    /// `id` is required, not defaulted: a stream nobody can cancel runs until the whole store is
    /// torn down, which for a reconnect loop or an engine subscription is a leak rather than a
    /// shortcut.
    public static func stream(
        id: AnyHashable,
        _ work: @escaping @MainActor (Send) async -> Void
    ) -> Effect {
        Effect(operation: .run(id: id, work: work))
    }

    /// Starts several effects together. Each keeps its own `id` and is cancelled independently.
    public static func merge(_ effects: Effect...) -> Effect {
        merge(effects)
    }

    /// Starts several effects together. Each keeps its own `id` and is cancelled independently.
    public static func merge(_ effects: [Effect]) -> Effect {
        Effect(operation: .merge(effects))
    }

    /// Cancels the in-flight effect tracked under `id`. A no-op when nothing is running under it,
    /// so a reducer can cancel defensively without first checking.
    public static func cancel(id: AnyHashable) -> Effect {
        Effect(operation: .cancel(id: id))
    }
}
