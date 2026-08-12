import Foundation

/// A navigation flow that can be started.
///
/// The coordinator owning a flow decides what comes next; its screens expose output closures it
/// injects and never hold a reference back. `start()` is the only universal requirement — child-flow
/// storage and subscription bags belong to the concrete coordinators that need them, not here.
public protocol Coordinator: AnyObject {

    /// Begins the flow, putting its first screen on screen.
    func start()
}
