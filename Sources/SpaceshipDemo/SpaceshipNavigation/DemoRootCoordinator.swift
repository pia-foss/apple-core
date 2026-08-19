#if canImport(UIKit) && !os(watchOS)

    import Combine
    import CoreArchitecture
    import SwiftUI
    import UIKit

    /// The demo's UIKit shell: it owns the navigation controller and the launch flow inside it.
    ///
    /// This is the parent half of the pattern, and the reason it is here rather than folded into
    /// `Spaceship.Coordinator`: retaining the child, subscribing before starting it, and cancelling the
    /// outgoing subscription first are the three things review has to catch, so they are worth seeing.
    ///
    /// It also shows the other half of the `Output` requirement. A root reports to nobody, so it declares
    /// no `Output` and inherits the `Never` default — `start()` is the whole of its conformance.
    @MainActor
    public final class DemoRootCoordinator: FlowCoordinator {

        /// The stack every flow in the demo pushes onto.
        public let navigationController = UINavigationController()

        private let log: TelemetryLog
        private var childCoordinator: (any FlowCoordinator)?
        private var cancellables = Set<AnyCancellable>()

        /// - Parameter log: Where telemetry and flow results are recorded.
        public init(log: TelemetryLog) {
            self.log = log
        }

        /// Starts the launch flow and subscribes to what it reports.
        ///
        /// `nonisolated` for the same reason as `Spaceship.Coordinator.start()`.
        public nonisolated func start() {
            Task { @MainActor in
                let coordinator = Spaceship.Coordinator(
                    navigationController: navigationController,
                    track: log.record
                )

                // Cancel before replacing the child: a subscription that outlives its coordinator
                // delivers into a flow this one has already let go of.
                cancellables.removeAll()
                childCoordinator = coordinator
                coordinator.output
                    .sink { [weak self] output in self?.handle(output) }
                    .store(in: &cancellables)

                coordinator.start()
            }
        }

        /// The parent decides what a finished flight means.
        ///
        /// Here it goes on the record; in a real app this is where the transition out of the flow lives.
        private func handle(_ output: Spaceship.Output) {
            switch output {
            case .flightFinished(let ship, let phase):
                log.record("\(ship.name): \(phase.title.lowercased())")
            }
        }
    }

    #if DEBUG

        /// Bridges the coordinator's stack into the canvas, so the UIKit flow is visible the same way
        /// `SpaceshipFlow` is.
        struct CoordinatorStackView: UIViewControllerRepresentable {

            let log: TelemetryLog

            func makeUIViewController(context: Context) -> UINavigationController {
                let root = DemoRootCoordinator(log: log)
                context.coordinator.root = root
                root.start()
                return root.navigationController
            }

            func updateUIViewController(_ controller: UINavigationController, context: Context) {}

            func makeCoordinator() -> Holder { Holder() }

            /// Retains the root coordinator for as long as the stack is on screen.
            ///
            /// Nothing else would: `makeUIViewController` returns the navigation controller, not the
            /// coordinator that configured it, so without this the flow would deallocate on the way out
            /// and take its subscription with it.
            final class Holder {
                var root: DemoRootCoordinator?
            }
        }

        /// The coordinator flow with the same telemetry panel the declarative demo carries.
        private struct CoordinatorDemoView: View {

            @StateObject private var log = TelemetryLog()

            var body: some View {
                CoordinatorStackView(log: log)
                    .safeAreaInset(edge: .bottom) {
                        TelemetryPanelView(entries: log.entries)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                    }
                    .preferredColorScheme(.dark)
            }
        }

        struct DemoRootCoordinator_Previews: PreviewProvider {
            static var previews: some View {
                CoordinatorDemoView()
            }
        }

    #endif

#endif
