import Foundation

/// The minimal navigation contract from ADR 0009: every coordinator, whether it orchestrates
/// children or presents a single screen, must be startable.
///
/// **A screen should never know what comes next.** That belongs to the coordinator owning the flow.
/// Views and view controllers hold no coordinator reference — they expose output closures the
/// coordinator injects, and the coordinator decides the transition. UIKit view controllers and
/// SwiftUI views use the identical pattern; the `UIHostingController` wrap is a coordinator detail.
///
/// A coordinator starts an MVI feature by creating its `Store` and handing it to the feature view.
/// The store owns state, the coordinator owns transitions — that is the whole seam between ADR 0010
/// and ADR 0009, and the reason this protocol lives next to `Store` rather than in an app target.
/// It is the single declaration for every Apple client: two app-local copies existed briefly and were
/// consolidated here.
///
/// ```swift
/// @MainActor
/// final class WelcomeBackCoordinator: Coordinator {
///     private let subject = PassthroughSubject<WelcomeBackOutput, Never>()
///     var output: AnyPublisher<WelcomeBackOutput, Never> { subject.eraseToAnyPublisher() }
///
///     func start() {
///         let store = Store(initial: …, reduce: WelcomeBackReducer(deps: .live).reduce)
///         let view = WelcomeBackView(store: store) { [weak self] in self?.subject.send(.signedIn) }
///         presenter.present(UIHostingController(rootView: view), animated: true)
///     }
/// }
/// ```
///
/// `childCoordinator` and `cancellables` are deliberately **not** requirements: they are
/// implementation details of coordinators that happen to own child flows or use Combine, and Swift
/// protocols cannot supply stored properties anyway. ADR 0009 reserves a separate, opt-in
/// `ParentCoordinator` protocol for the day several coordinators genuinely need to declare child
/// ownership — until then, declare the properties on the concrete type.
///
/// Discipline the compiler will not enforce for you, so review must (ADR 0009):
/// - capture `self` as `weak` in every injected closure, or the coordinator and the closure it
///   handed out retain each other;
/// - store every subscription in `cancellables` — one that is not stored is cancelled immediately
///   and silently;
/// - call `cancellables.removeAll()` before replacing a child coordinator, so the outgoing child's
///   output subscription dies with it.
public protocol Coordinator: AnyObject {
    func start()
}
