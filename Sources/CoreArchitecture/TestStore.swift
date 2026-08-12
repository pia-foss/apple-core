#if DEBUG

    import Foundation

    /// A deterministic driver for a reducer under test — the safety net ADR 0010 names as missing.
    ///
    /// It runs the same reducer and the same effect machinery as `Store`, so cancellation and
    /// merging behave identically under test and in the app. The one difference is deliberate:
    /// actions produced by effects are **queued rather than applied**. The test decides when to let
    /// them in, which is what makes an async round-trip assertable instead of raced.
    ///
    /// ```swift
    /// let store = TestStore(
    ///     initial: WelcomeBackState(subscription: subscription),
    ///     reduce: WelcomeBackReducer(deps: .init(recover: { _ in .signedIn }, track: spy.track)).reduce
    /// )
    ///
    /// store.send(.recoverTapped)                              // reducer runs synchronously
    /// XCTAssertEqual(store.state.phase, .recovering)
    ///
    /// let action = await store.receive()                      // the effect's follow-up, applied
    /// XCTAssertEqual(action, .recoverResult(.signedIn))
    /// XCTAssertEqual(store.state.phase, .recovered)
    ///
    /// await store.finish()                                    // drain fire-and-forget work
    /// XCTAssertEqual(spy.events, [.recoverTapped, .recoverSucceeded])
    /// ```
    ///
    /// `DEBUG`-only, so it costs nothing in a release build. Test targets compile in Debug, which is
    /// where it is needed.
    @MainActor
    public final class TestStore<State, Action> {

        /// The current state, after every action the test has sent or received.
        public private(set) var state: State

        private let _reduce: (inout State, Action) -> Effect<Action>?
        private let tasks = EffectRuntime.Tasks()

        /// Actions produced by effects that `receive(timeout:)` has not consumed yet.
        private var queued: [Action] = []

        private var waiter: CheckedContinuation<Action?, Never>?
        private var timeoutTask: Task<Void, Never>?

        public init(initial: State, reduce: @escaping (inout State, Action) -> Effect<Action>?) {
            self.state = initial
            self._reduce = reduce
        }

        deinit {
            tasks.cancelAll()
        }

        /// Sends an action as the user would: runs the reducer synchronously and starts any effect
        /// it returns. Assert on `state` immediately afterwards to check the synchronous mutation.
        public func send(_ action: Action) {
            guard let effect = _reduce(&state, action) else { return }
            start(effect)
        }

        /// Waits for the next action an effect produced, applies it through the reducer, and returns
        /// it so the test can assert what it was.
        ///
        /// Returns `nil` if `timeout` elapses first; asserting the result is non-`nil` turns a
        /// missing action into a readable failure. Kept free of any XCTest dependency so the type
        /// works from both XCTest and Swift Testing.
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

        /// Actions an effect has produced that no `receive(timeout:)` has consumed. Assert this is
        /// zero at the end of a test to catch an effect that fired more than expected.
        public var unconsumedActionCount: Int { queued.count }

        /// Waits for in-flight effects to finish, then cancels anything left — a `.stream` effect
        /// never finishes on its own.
        ///
        /// Use it to drain fire-and-forget work (analytics, persistence) before asserting on a spy.
        /// Actions still queued are left in place for `receive(timeout:)`.
        public func finish(timeout: TimeInterval = 1) async {
            let deadline = Date().addingTimeInterval(timeout)
            // Polls rather than awaiting each task: tasks self-deregister as they complete, and the
            // set can grow while we wait (one effect starting another). 1ms keeps the main actor
            // free without adding meaningful latency to a test.
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
