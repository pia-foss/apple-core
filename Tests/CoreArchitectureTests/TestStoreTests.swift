import Testing

@testable import CoreArchitecture

@MainActor
struct TestStoreTests {

    private struct LoadState: Equatable {
        var loading = false
        var value = 0
    }

    private enum LoadAction: Equatable {
        case loadRequested
        case loaded(Int)
    }

    private func reduce(_ state: inout LoadState, _ action: LoadAction) -> Effect<LoadAction>? {
        switch action {
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
    func sendAppliesTheSynchronousMutationOnly() async {
        let store = TestStore(initial: LoadState(), reduce: reduce)

        store.send(.loadRequested)

        // The effect's action is queued, not applied — that is what makes the round-trip assertable
        // rather than raced.
        #expect(store.state == LoadState(loading: true, value: 0))
    }

    @Test
    func receiveReturnsTheEffectsActionAndAppliesIt() async {
        let store = TestStore(initial: LoadState(), reduce: reduce)
        store.send(.loadRequested)

        let received = await store.receive()

        #expect(received == .loaded(42))
        #expect(store.state == LoadState(loading: false, value: 42))
        #expect(store.unconsumedActionCount == 0)
    }

    @Test
    func receiveReturnsNilWhenNoActionArrivesBeforeTheTimeout() async {
        let store = TestStore(initial: LoadState(), reduce: reduce)

        // Nothing was sent, so no effect is running and nothing will ever arrive.
        let received = await store.receive(timeout: 0.05)

        #expect(received == nil)
    }

    @Test
    func streamActionsAreReceivedInOrder() async {
        struct State: Equatable {
            var ticks: [Int] = []
        }
        enum Action: Equatable {
            case start
            case tick(Int)
        }

        let store = TestStore(initial: State()) {
            (state: inout State, action: Action) -> Effect<Action>? in
            switch action {
            case .start:
                return .stream(id: "ticks") { send in
                    for tick in 1...3 {
                        send(.tick(tick))
                    }
                }
            case .tick(let tick):
                state.ticks.append(tick)
                return nil
            }
        }

        store.send(.start)

        for expected in 1...3 {
            let received = await store.receive()
            #expect(received == .tick(expected))
        }
        #expect(store.state.ticks == [1, 2, 3])
        await store.finish()
    }

    @Test
    func finishDrainsFireAndForgetWorkBeforeAssertingOnASpy() async {
        final class Spy {
            var calls: [String] = []
        }
        let spy = Spy()

        enum Action {
            case declineTapped
        }

        let store = TestStore(initial: 0) { (_: inout Int, action: Action) -> Effect<Action>? in
            switch action {
            case .declineTapped:
                return .fireAndForget { spy.calls.append("declined") }
            }
        }

        store.send(.declineTapped)
        await store.finish()

        #expect(spy.calls == ["declined"])
    }

    @Test
    func unconsumedActionCountRevealsAnEffectThatFiredMoreThanExpected() async {
        struct State: Equatable {
            var ticks = 0
        }
        enum Action: Equatable {
            case start
            case tick
        }

        let store = TestStore(initial: State()) {
            (state: inout State, action: Action) -> Effect<Action>? in
            switch action {
            case .start:
                return .stream(id: "ticks") { send in
                    send(.tick)
                    send(.tick)
                }
            case .tick:
                state.ticks += 1
                return nil
            }
        }

        store.send(.start)
        _ = await store.receive()

        // One action consumed, one still queued — the assertion that catches an over-firing effect.
        #expect(store.state.ticks == 1)
        #expect(store.unconsumedActionCount == 1)
        await store.finish()
    }
}
