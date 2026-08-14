import Combine
import Foundation
import Testing

@testable import CoreArchitecture

@MainActor
struct StoreTests {

    private struct CounterState: Equatable {
        var value = 0
        var loading = false
    }

    private enum CounterAction: Equatable {
        case increment
        case loadRequested
        case loaded(Int)
    }

    /// A reducer with a pure mutation and an effect that emits a follow-up action.
    private func reduce(
        _ state: inout CounterState,
        _ action: CounterAction
    ) -> Effect<CounterAction>? {
        switch action {
        case .increment:
            state.value += 1
            return nil
        case .loadRequested:
            state.loading = true
            return .task { .loaded(42) }
        case .loaded(let value):
            state.loading = false
            state.value = value
            return nil
        }
    }

    @Test
    func pureActionMutatesStateSynchronously() {
        let store = Store(initial: CounterState(), reduce: reduce)

        store.send(.increment)

        #expect(store.state == CounterState(value: 1))
    }

    @Test
    func effectFeedsFollowUpActionBackIntoStore() async {
        let store = Store(initial: CounterState(), reduce: reduce)

        store.send(.loadRequested)
        // The reducer set loading synchronously before the effect ran.
        #expect(store.state.loading)

        // Wait for the effect's follow-up `.loaded` action to flow back through `send`.
        await waitFor { store.state == CounterState(value: 42, loading: false) }
        #expect(store.state == CounterState(value: 42, loading: false))
    }

    // MARK: - fireAndForget

    private struct SideEffectState: Equatable {
        var actionsApplied = 0
    }

    private enum SideEffectAction: Equatable {
        case start
        case applied
    }

    @Test
    func fireAndForgetRunsWorkWithoutProducingAnAction() async {
        final class Spy {
            var calls = 0
        }
        let spy = Spy()
        let store = Store(initial: SideEffectState()) {
            (state: inout SideEffectState, action: SideEffectAction) -> Effect<SideEffectAction>? in
            switch action {
            case .start:
                return .fireAndForget { spy.calls += 1 }
            case .applied:
                state.actionsApplied += 1
                return nil
            }
        }

        store.send(.start)

        await waitFor { spy.calls == 1 }
        #expect(spy.calls == 1)
        // No follow-up action was fed back — that is the whole point of fire-and-forget.
        #expect(store.state.actionsApplied == 0)
    }

    @Test
    func mergeStartsEveryEffect() async {
        final class Spy {
            var calls = 0
        }
        let spy = Spy()
        let store = Store(initial: SideEffectState()) {
            (state: inout SideEffectState, action: SideEffectAction) -> Effect<SideEffectAction>? in
            switch action {
            case .start:
                return .merge(
                    .fireAndForget { spy.calls += 1 },
                    .task { .applied }
                )
            case .applied:
                state.actionsApplied += 1
                return nil
            }
        }

        store.send(.start)

        await waitFor { spy.calls == 1 && store.state.actionsApplied == 1 }
        #expect(spy.calls == 1)
        #expect(store.state.actionsApplied == 1)
    }

    // MARK: - Streams and cancellation

    private struct StreamState: Equatable {
        var ticks: [Int] = []
        /// Generations whose stream observed cancellation, in the order they noticed.
        var cancelled: [Int] = []
    }

    private enum StreamAction: Equatable {
        /// Starts a long-lived stream tagged with a generation number.
        case start(Int)
        case stop
        case tick(Int)
        case cancelled(Int)
    }

    private static let streamID = "stream"

    /// A stream that emits three ticks and then parks.
    ///
    /// Parking lets a later action cancel it, and the generation number makes it visible *which*
    /// stream reported.
    private func reduceStream(
        _ state: inout StreamState,
        _ action: StreamAction
    ) -> Effect<StreamAction>? {
        switch action {
        case .start(let generation):
            return .stream(id: Self.streamID) { send in
                for tick in 1...3 {
                    send(.tick(tick))
                }
                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                } catch {
                    // Cancellation arrives as a thrown error from the sleep. The task is cancelled,
                    // not killed, so it can still report before returning.
                    send(.cancelled(generation))
                }
            }
        case .stop:
            return .cancel(id: Self.streamID)
        case .tick(let tick):
            state.ticks.append(tick)
            return nil
        case .cancelled(let generation):
            state.cancelled.append(generation)
            return nil
        }
    }

    @Test
    func streamEmitsMultipleActionsFromOneEffect() async {
        let store = Store(initial: StreamState(), reduce: reduceStream)

        store.send(.start(1))

        await waitFor { store.state.ticks == [1, 2, 3] }
        #expect(store.state.ticks == [1, 2, 3])
    }

    @Test
    func cancelByIDTearsDownTheInFlightStream() async {
        let store = Store(initial: StreamState(), reduce: reduceStream)
        store.send(.start(1))
        await waitFor { store.state.ticks == [1, 2, 3] }

        store.send(.stop)

        await waitFor { store.state.cancelled == [1] }
        #expect(store.state.cancelled == [1])
    }

    @Test
    func sameIDCancelsTheEffectAlreadyInFlight() async {
        let store = Store(initial: StreamState(), reduce: reduceStream)
        store.send(.start(1))
        await waitFor { store.state.ticks == [1, 2, 3] }

        // Same id means one at a time: generation 2 evicts generation 1.
        store.send(.start(2))

        await waitFor { store.state.cancelled == [1] }
        #expect(store.state.cancelled == [1])
    }

    @Test
    func distinctIDsRunConcurrently() async {
        let store = Store(initial: StreamState()) {
            (state: inout StreamState, action: StreamAction) -> Effect<StreamAction>? in
            switch action {
            case .start(let generation):
                // A distinct id per generation, so neither evicts the other.
                return .stream(id: generation) { send in
                    do {
                        try await Task.sleep(nanoseconds: 60_000_000_000)
                    } catch {
                        send(.cancelled(generation))
                    }
                }
            case .stop:
                return .merge(.cancel(id: 1), .cancel(id: 2))
            case .tick:
                return nil
            case .cancelled(let generation):
                state.cancelled.append(generation)
                return nil
            }
        }

        store.send(.start(1))
        store.send(.start(2))
        store.send(.stop)

        await waitFor { store.state.cancelled.count == 2 }
        #expect(Set(store.state.cancelled) == [1, 2])
    }

    @Test
    func cancelAllEffectsStopsEverythingStillTracked() async {
        let store = Store(initial: StreamState(), reduce: reduceStream)
        store.send(.start(1))
        await waitFor { store.state.ticks == [1, 2, 3] }

        store.cancelAllEffects()

        await waitFor { store.state.cancelled == [1] }
        #expect(store.state.cancelled == [1])
    }

    // MARK: - Helpers

    /// Polls `condition` on the main actor until it holds or the timeout elapses.
    ///
    /// Avoids depending on wall-clock sleeps for the effect round-trip.
    private func waitFor(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)  // 5ms
        }
    }
}
