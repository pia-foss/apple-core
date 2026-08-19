#if canImport(UIKit) && !os(watchOS)

    import Combine
    import CoreArchitecture
    import UIKit
    import XCTest

    @testable import SpaceshipDemo

    /// What a window-less test can still reach of the UIKit flow: starting it puts a screen on the stack,
    /// and the parent wires and starts its child.
    ///
    /// Deliberately thin, and the thinness is the finding. `FlowReducerTests` asserts the same transitions —
    /// push, back, cross-feature result — as plain function calls, because `Flow` keeps them in state. Here a
    /// selection can only be made by tapping, so nothing past the first push is reachable without a window.
    ///
    /// - Note: behind the same UIKit guard as the code it covers, so `swift test` on macOS skips this file.
    ///   Reaching it needs an iOS destination.
    @MainActor
    final class SpaceshipCoordinatorTests: XCTestCase {

        func test_start_putsFleetScreenOnTheStack() async {
            let navigation = UINavigationController()
            let coordinator = Spaceship.Coordinator(navigationController: navigation, track: { _ in })

            coordinator.start()
            await settle()

            XCTAssertEqual(navigation.viewControllers.count, 1)
            XCTAssertEqual(navigation.topViewController?.title, "Fleet")
        }

        /// Nothing is reported until a flight finishes, so a parent that subscribes at once hears silence.
        func test_start_reportsNothingOnItsOwn() async {
            let navigation = UINavigationController()
            let coordinator = Spaceship.Coordinator(navigationController: navigation, track: { _ in })
            var received: [Spaceship.Output] = []
            let token = coordinator.output.sink { received.append($0) }

            coordinator.start()
            await settle()

            XCTAssertTrue(received.isEmpty)
            token.cancel()
        }

        /// The parent's whole job, asserted through its only visible effect: the child ran.
        func test_root_startsTheLaunchFlow() async {
            let root = DemoRootCoordinator(log: TelemetryLog())

            root.start()
            await settle()

            XCTAssertEqual(root.navigationController.viewControllers.count, 1)
            XCTAssertEqual(root.navigationController.topViewController?.title, "Fleet")
        }

        /// Lets the main-actor hop inside `start()` run.
        ///
        /// `start()` is `nonisolated` and does its work in a `Task`, so the push has not happened by the time
        /// it returns. Yielding rather than sleeping keeps the test off the wall clock.
        private func settle(yields: Int = 10) async {
            for _ in 0..<yields {
                await Task.yield()
            }
        }
    }

#endif
