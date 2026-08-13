#if DEBUG

    import Foundation

    /// A deterministic driver for exercising a reducer and its effects in tests.
    ///
    /// Runs the same reducer and effect machinery as `Store`, so cancellation and merging behave
    /// identically. The one difference is deliberate: actions produced by effects are queued rather
    /// than applied, and the test decides when to let them in — which is what makes an async
    /// round-trip assertable instead of raced.
    ///
    /// - Note: `DEBUG`-only, so it costs nothing in a release build.
    @MainActor
    public final class TestStore<State, Action> {

        /// The current state, after every action the test has sent or received.
        public private(set) var state: State

        /// Actions produced by effects that `receive(timeout:)` has not consumed.
        ///
        /// Assert this is zero at the end of a test to catch an effect that fired more than expected.
        public var unconsumedActionCount: Int { queued.count }

        private let _reduce: (inout State, Action) -> Effect<Action>?
        private let tasks = EffectRuntime.Tasks()
        private var queued: [Action] = []
        private var waiter: CheckedContinuation<Action?, Never>?
        private var timeoutTask: Task<Void, Never>?

        /// Creates a test store seeded with `initial`, reducing actions with `reduce`.
        ///
        /// - Parameters:
        ///   - initial: The state the feature starts in.
        ///   - reduce: The reducer under test.
        public init(initial: State, reduce: @escaping (inout State, Action) -> Effect<Action>?) {
            self.state = initial
            self._reduce = reduce
        }

        deinit {
            tasks.cancelAll()
        }

        /// Sends an action as a view would, running the reducer and starting any effect it returns.
        ///
        /// Assert on `state` immediately afterwards to check the synchronous mutation.
        public func send(_ action: Action) {
            guard let effect = _reduce(&state, action) else { return }
            start(effect)
        }

        /// Waits for the next action an effect produced, applies it, and returns it for assertion.
        ///
        /// Takes no XCTest dependency, so it serves XCTest and Swift Testing alike.
        ///
        /// - Parameter timeout: Seconds to wait before giving up.
        /// - Returns: The action applied, or `nil` if `timeout` elapsed first.
        public func receive(timeout: TimeInterval = 1) async -> Action? {
            let action: Action?
            if queued.isEmpty {
                action = await waitForAction(timeout: timeout)
            } else {
                action = queued.removeFirst()
            }
            guard let action else { return nil }
            if let effect = _reduce(&state, action) {
                start(effect)
            }
            return action
        }

        /// Waits for in-flight effects to finish, then cancels whatever is left.
        ///
        /// Drains fire-and-forget work before asserting on a spy. A `stream` effect never finishes on
        /// its own, hence the cancel. Queued actions are left for `receive(timeout:)`.
        ///
        /// - Parameter timeout: Seconds to wait before cancelling.
        public func finish(timeout: TimeInterval = 1) async {
            let deadline = Date().addingTimeInterval(timeout)
            // Polls rather than awaiting each task, because tasks self-deregister as they complete and
            // the set can grow while we wait — one effect may start another.
            while !tasks.isEmpty && Date() < deadline {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            tasks.cancelAll()
        }

        // MARK: - Effect plumbing

        private func start(_ effect: Effect<Action>) {
            EffectRuntime.run(effect, tasks: tasks) { [weak self] action in
                self?.enqueue(action)
            }
        }

        /// Hands the action to a waiting `receive`, or queues it until one arrives.
        private func enqueue(_ action: Action) {
            if waiter != nil {
                resumeWaiter(with: action)
            } else {
                queued.append(action)
            }
        }

        private func waitForAction(timeout: TimeInterval) async -> Action? {
            await withCheckedContinuation { continuation in
                waiter = continuation
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    // Cancelled means the waiter was already resumed with a real action.
                    guard !Task.isCancelled else { return }
                    self?.resumeWaiter(with: nil)
                }
            }
        }

        private func resumeWaiter(with action: Action?) {
            guard let waiter else { return }
            self.waiter = nil
            timeoutTask?.cancel()
            timeoutTask = nil
            waiter.resume(returning: action)
        }
    }

#endif
