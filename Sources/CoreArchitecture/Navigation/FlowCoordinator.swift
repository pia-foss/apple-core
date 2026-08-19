import Combine
import Foundation

/// A screen flow that can be started.
///
/// The coordinator owning a flow decides what comes next; its screens expose output closures it
/// injects and never hold a reference back. `start()` is the only universal requirement — child-flow
/// storage and subscription bags stay with the concrete coordinators that need them, and a protocol
/// cannot supply stored properties anyway.
///
/// - Note: named for the flow it drives rather than for the pattern, which leaves `Coordinator` free
///   as the concrete name inside a feature namespace: `Feature.Coordinator: FlowCoordinator`.
public protocol FlowCoordinator: AnyObject {

    /// Begins the flow, putting its first screen on screen.
    func start()
}

/// A flow that reports its results to whoever started it.
///
/// Separate from `FlowCoordinator` so the requirement stays real. On the base protocol it would need a
/// default for the roots and leaves that report nothing, and a default publisher silently satisfies a
/// conformer that meant to report something.
///
/// - Note: keeping the associated type off the base protocol is also what lets a parent hold children
///   of differing flows side by side as `any FlowCoordinator`.
public protocol ReportingFlowCoordinator: FlowCoordinator {

    /// What the flow reports upward.
    associatedtype Output

    /// Results the flow reports upward, for its parent to subscribe to.
    ///
    /// The flow fires and the parent decides the transition, so neither knows the other's internals.
    /// It cannot fail: a flow surfaces its own errors on its own screens.
    var output: AnyPublisher<Output, Never> { get }
}
