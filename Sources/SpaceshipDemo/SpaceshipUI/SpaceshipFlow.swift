import CoreArchitecture
import SwiftUI

/// The demo's entry point, and the seam between its two screens.
///
/// Not a screen: it renders none of its own. It owns the coordination store — the navigation stack and the
/// result of each launch — and creates a `Launch` store for every ship pushed. Each screen owns its own
/// feature store, so nothing here reaches into one.
///
/// - Note: Requires iOS 16 for `NavigationStack`. The library itself still supports iOS 15; only this demo
///   asks for more.
@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
public struct SpaceshipFlow: View {

    @StateObject private var flowStore: Store<Flow.State, Flow.Action>
    @StateObject private var log: TelemetryLog

    /// Creates the flow with real components, real waits, and a fresh telemetry log.
    public init() {
        let log = TelemetryLog()
        _log = StateObject(wrappedValue: log)
        _flowStore = StateObject(
            wrappedValue: Store(
                initial: Flow.State(),
                reduce: Flow.Reducer(dependencies: .init(track: log.record)).reduce
            )
        )
    }

    /// A navigation stack whose path is the fleet's own state, with telemetry pinned below it.
    ///
    /// `binding` is what avoids a second source of truth: the stack reads the path from state, and every
    /// change it makes — a push, the back button, a back-swipe — returns as `.pathChanged`.
    public var body: some View {
        NavigationStack(path: flowStore.binding(\.path) { .pathChanged($0) }) {
            FleetScreen(
                dependencies: .live,
                results: flowStore.state.results,
                onSelect: { flowStore.send(.shipSelected($0)) }
            )
            .navigationTitle("Fleet")
            .navigationDestination(for: Spaceship.Ship.self, destination: launchScreen)
        }
        .safeAreaInset(edge: .bottom) {
            TelemetryPanelView(entries: log.entries)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
    }

    /// Builds the launch screen for `ship`, with its own store behind it.
    ///
    /// Both handoffs happen here and nowhere else. Going down, the recorded result seeds the launch state, so
    /// reopening a ship that reached orbit does not claim it is grounded. Coming up, `reportResult` turns a
    /// final phase into a `Flow` action. Neither feature imports the other.
    private func launchScreen(for ship: Spaceship.Ship) -> some View {
        LaunchScreen(
            state: Launch.State(ship: ship, phase: flowStore.state.results[ship.id] ?? .grounded),
            dependencies: .live(
                track: log.record,
                reportResult: { [flowStore] phase in
                    flowStore.send(.flightFinished(shipID: ship.id, phase: phase))
                }
            )
        )
        .navigationTitle(ship.name)
    }
}

/// Ground control's view of the telemetry a `fireAndForget` effect sent out.
///
/// It reads the log rather than either store, which is the distinction worth noticing: telemetry leaves a
/// feature and never comes back as state.
struct TelemetryPanelView: View {

    let entries: [String]

    /// The newest few entries.
    ///
    /// Older lines drop off rather than growing the panel without bound.
    private var visible: [String] { Array(entries.suffix(4)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Ground control", systemImage: "antenna.radiowaves.left.and.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))

            if visible.isEmpty {
                Text("Awaiting telemetry")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.35))
            } else {
                ForEach(Array(visible.enumerated()), id: \.offset) { _, entry in
                    Text(entry)
                        .font(.caption.monospaced())
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .demoCard(padding: 12)
    }
}

#if DEBUG

    /// Runs on `.live` dependencies so the flight unfolds at a watchable pace.
    ///
    /// `.immediate` belongs in tests: with no waits the countdown and ascent complete inside one frame, so
    /// the canvas would only ever show the final phase and Abort would never be tappable.
    @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
    struct SpaceshipFlow_Previews: PreviewProvider {
        static var previews: some View {
            SpaceshipFlow()
        }
    }

#endif
