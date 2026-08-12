import Foundation

extension Spaceship {

    /// The collaborators that keep `Spaceship.Reducer` pure.
    ///
    /// All three are typed closures rather than protocols, because each is one operation used by one
    /// feature. A collaborator shared across features would earn a protocol instead.
    public struct Dependencies {

        /// Runs the pre-flight checks and reports whether they passed.
        ///
        /// Not main-actor isolated, so awaiting it releases the main thread for the real work.
        public var runPreflightChecks: () async -> Bool

        /// Suspends for a number of seconds.
        ///
        /// Time is a dependency for the same reason the network is: a test that waited three real
        /// seconds for a countdown would be three seconds slower and no more correct.
        public var wait: (TimeInterval) async -> Void

        /// Sends a line of telemetry to ground control.
        ///
        /// Main-actor isolated so an effect body can call it without `await`.
        public var track: @MainActor (String) -> Void

        /// Creates a dependency set from its three collaborators.
        ///
        /// - Parameters:
        ///   - runPreflightChecks: Reports whether the checks passed.
        ///   - wait: Suspends for a number of seconds.
        ///   - track: Receives a line of telemetry.
        public init(
            runPreflightChecks: @escaping () async -> Bool,
            wait: @escaping (TimeInterval) async -> Void,
            track: @escaping @MainActor (String) -> Void
        ) {
            self.runPreflightChecks = runPreflightChecks
            self.wait = wait
            self.track = track
        }
    }
}

extension Spaceship.Dependencies {

    /// Wiring for the running app, with real waits and telemetry going to `log`.
    ///
    /// - Parameter log: The sink telemetry is recorded into.
    /// - Returns: Dependencies suitable for a real flight.
    public static func live(log: TelemetryLog) -> Self {
        Self(
            runPreflightChecks: {
                try? await Task.sleep(nanoseconds: 600_000_000)
                return true
            },
            wait: { seconds in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            },
            track: { [weak log] message in log?.record(message) }
        )
    }

    /// Wiring that never waits, for tests and previews.
    ///
    /// - Parameters:
    ///   - checksPass: What `runPreflightChecks` should report.
    ///   - track: Where telemetry goes. Defaults to discarding it.
    /// - Returns: Dependencies that resolve immediately.
    public static func immediate(
        checksPass: Bool = true,
        track: @escaping @MainActor (String) -> Void = { _ in }
    ) -> Self {
        Self(
            runPreflightChecks: { checksPass },
            wait: { _ in },
            track: track
        )
    }
}
