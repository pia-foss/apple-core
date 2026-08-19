import Combine
import Testing

@testable import CoreArchitecture

/// Covers what the `Output` requirement has to guarantee: a flow with nobody to report to conforms
/// without declaring one, a flow whose namespace already owns an `Output` type still infers the
/// associated type from its publisher, and the protocol stays usable as a plain existential.
///
/// Those are compile-time claims, so the declarations below are the real assertions — the runtime
/// checks confirm the wiring they imply.
struct FlowCoordinatorTests {

    /// A flow with nobody above it to report to, conforming with only `start()`.
    ///
    /// That this compiles without an `Output` or a publisher is the assertion.
    private final class Coordinator: FlowCoordinator {
        var didStart = false
        func start() { didStart = true }
    }

    /// Mirrors a feature namespace owning both an `Output` type and a `Coordinator`, which is where
    /// unqualified `Output` could have resolved to the associated type instead of the nested enum.
    private enum Onboarding {

        enum Output: Equatable {
            case didFinish(name: String)
            case didCancel
        }

        final class Coordinator: FlowCoordinator {

            private let subject = PassthroughSubject<Output, Never>()
            var output: AnyPublisher<Output, Never> { subject.eraseToAnyPublisher() }

            func start() { subject.send(.didFinish(name: "Ada")) }
        }
    }

    @Test
    func flowWithNoOutputStartsWithoutDeclaringOne() {
        let coordinator = Coordinator()

        coordinator.start()

        #expect(coordinator.didStart)
    }

    /// The default publisher reports completion rather than staying open, so a parent that subscribes
    /// to a flow with no output is not left holding a live subscription.
    ///
    /// Completion is the only thing worth asserting: `Output == Never` already makes a value
    /// unrepresentable, so `receiveValue` is uninhabited rather than merely unexercised.
    @Test
    func defaultOutputCompletesImmediately() {
        var didComplete = false

        let token = Coordinator().output.sink(
            receiveCompletion: { _ in didComplete = true },
            receiveValue: { _ in }
        )

        #expect(didComplete)
        token.cancel()
    }

    /// The nested `Output` wins the name lookup, so the flow reports its own cases.
    @Test
    func flowWithNestedOutputDeliversItsOwnCases() {
        let coordinator = Onboarding.Coordinator()
        var received: [Onboarding.Output] = []
        let token = coordinator.output.sink { received.append($0) }

        coordinator.start()

        #expect(received == [.didFinish(name: "Ada")])
        token.cancel()
    }

    /// A parent can subscribe without knowing the concrete coordinator, which is what makes the
    /// requirement worth stating on a protocol at all.
    @Test
    func outputIsReachableGenerically() {
        let coordinator = Onboarding.Coordinator()
        var received: [Onboarding.Output] = []

        let token = subscribe(to: coordinator) { received.append($0) }
        coordinator.start()

        #expect(received == [.didFinish(name: "Ada")])
        token.cancel()
    }

    /// A parent can hold children of differing flows in one collection, despite the associated type.
    ///
    /// Reaching `output` on one of them needs a generic context, as `subscribe(to:handle:)` provides.
    @Test
    func flowsOfDifferingOutputsShareACollection() {
        let reporting = Onboarding.Coordinator()
        let silent = Coordinator()
        let children: [any FlowCoordinator] = [reporting, silent]

        children.forEach { $0.start() }

        #expect(silent.didStart)
    }

    private func subscribe<C: FlowCoordinator>(
        to coordinator: C,
        handle: @escaping (C.Output) -> Void
    ) -> AnyCancellable {
        coordinator.output.sink { handle($0) }
    }
}
