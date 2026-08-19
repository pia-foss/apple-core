import Combine
import Foundation

/// A screen flow that can be started, and that reports its results to whoever started it.
///
/// The coordinator owning a flow decides what comes next; its screens expose output closures it
/// injects and never hold a reference back. Child-flow storage and subscription bags stay with the
/// concrete coordinators that need them — a protocol cannot supply stored properties.
///
/// - Note: named for the flow it drives rather than for the pattern, which leaves `Coordinator` free
///   as the concrete name inside a feature namespace: `Feature.Coordinator: FlowCoordinator`.
public protocol FlowCoordinator: AnyObject {

    /// What the flow reports upward.
    ///
    /// Defaults to `Never` for a flow with nobody above it to report to, which the extension below
    /// then supplies the publisher for.
    associatedtype Output = Never

    /// Results the flow reports upward, for its parent to subscribe to.
    ///
    /// The flow fires and the parent decides the transition, so neither knows the other's internals.
    /// It cannot fail: a flow surfaces its own errors on its own screens.
    var output: AnyPublisher<Output, Never> { get }

    /// Begins the flow, putting its first screen on screen.
    func start()
}

extension FlowCoordinator where Output == Never {

    /// A flow that reports nothing upward — an app root, or a leaf whose parent needs no result.
    ///
    /// Completes immediately rather than staying open: there is nothing to wait for, and a
    /// subscription that never completes would retain its sink for the coordinator's lifetime.
    public var output: AnyPublisher<Never, Never> { Empty().eraseToAnyPublisher() }
}
