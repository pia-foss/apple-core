import CoreArchitecture
import SwiftUI

/// The demo's entry point: a real navigation stack driven entirely by state.
///
/// Owns the store, reads `store.state`, dispatches with `store.send(_:)`, and decides nothing. Lives in
/// the UI target, which cannot be imported by `SpaceshipFeature` — the layering is a build error rather
/// than a convention.
///
/// - Note: Requires iOS 16 for `NavigationStack`. The library itself still supports iOS 15; only this demo
///   asks for more.
@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
public struct SpaceshipView: View {

    @StateObject private var store: Store<Spaceship.State, Spaceship.Action>
    @StateObject private var log: TelemetryLog

    /// Creates the screen with real components, real waits, and a fresh telemetry log.
    public init() {
        let log = TelemetryLog()
        self.init(dependencies: .live(track: log.record), log: log)
    }

    /// Creates the screen with explicit dependencies, for previews and tests.
    ///
    /// - Parameters:
    ///   - dependencies: The collaborators the reducer runs through.
    ///   - log: The telemetry sink the panel renders.
    public init(dependencies: Spaceship.Dependencies, log: TelemetryLog) {
        _log = StateObject(wrappedValue: log)
        _store = StateObject(
            wrappedValue: Store(
                initial: Spaceship.State(),
                reduce: Spaceship.Reducer(deps: dependencies).reduce
            )
        )
    }

    /// A navigation stack whose path is the feature's own state.
    ///
    /// `store.binding` is what makes this work without a second source of truth: the stack reads the path
    /// from state, and every change it makes — a push, the back button, a back-swipe — comes back as
    /// `.pathChanged` for the reducer to handle. That is why swiping back cancels a running countdown.
    public var body: some View {
        NavigationStack(path: store.binding(\.path) { .pathChanged($0) }) {
            FleetView(
                fleet: store.state.fleet,
                isLoading: store.state.isLoadingFleet,
                flights: store.state.flights,
                send: store.send
            )
            .navigationTitle("Fleet")
            .navigationDestination(for: Spaceship.Ship.ID.self) { id in
                // The reducer registers a flight before pushing, so this always resolves; the type system
                // just cannot say so across a dictionary lookup.
                if let flight = store.state.flights[id] {
                    LaunchView(flight: flight, send: store.send)
                        .navigationTitle(flight.ship.name)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            TelemetryPanel(entries: log.entries)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
    }
}

/// Ground control's view of the telemetry a `fireAndForget` effect sent out.
///
/// It reads the log rather than the store, which is the distinction worth noticing: telemetry leaves the
/// feature and never comes back as state.
struct TelemetryPanel: View {

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
    struct SpaceshipView_Previews: PreviewProvider {
        static var previews: some View {
            SpaceshipView()
        }
    }

#endif
