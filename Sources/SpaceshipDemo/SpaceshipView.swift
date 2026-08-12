import CoreArchitecture
import SwiftUI

/// The launch screen, and the demo's entry point.
///
/// Owns the store, reads `store.state`, dispatches with `store.send(_:)`. Nothing here decides what
/// happens next — the reducer does. The view stays outside the `Spaceship` namespace because in a real
/// project it is the per-app layer, while the namespace is the shareable part.
public struct SpaceshipView: View {

    @StateObject private var store: Store<Spaceship.State, Spaceship.Action>
    @StateObject private var log: TelemetryLog

    /// Creates the screen with real waits and a fresh telemetry log.
    public init() {
        let log = TelemetryLog()
        self.init(dependencies: .live(log: log), log: log)
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

    /// The screen's layout, top to bottom: phase, spaceship, controls, telemetry.
    public var body: some View {
        VStack(spacing: 28) {
            Text(store.state.phase.title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            AltitudeGauge(
                altitude: store.state.altitude,
                isAscending: store.state.phase == .ascending
            )

            // A slice of state plus `send`, passed as plain arguments. The sub-views below know
            // nothing about `Store`, which is what keeps them reusable and previewable.
            LaunchControls(phase: store.state.phase, send: store.send)

            TelemetryPanel(entries: log.entries)
        }
        .padding(24)
        .frame(maxWidth: 420)
    }
}

/// The spaceship and its altitude readout.
private struct AltitudeGauge: View {

    let altitude: Int
    let isAscending: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(isAscending ? "🚀" : "🛰")
                .font(.system(size: 56))
                .offset(y: -CGFloat(altitude) / 4)

            Text("\(altitude) km")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(height: 120)
    }
}

/// The pilot's buttons, enabled according to `phase`.
///
/// Which buttons make sense is a function of the phase alone, so this view needs no state of its own.
private struct LaunchControls: View {

    let phase: Spaceship.State.Phase
    let send: (Spaceship.Action) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Launch") { send(.launchTapped) }
                .disabled(phase != .grounded)

            Button("Abort") { send(.abortTapped) }
                .disabled(!phase.isInFlight)

            Button("Reset") { send(.resetTapped) }
                .disabled(phase == .grounded)
        }
        .buttonStyle(.bordered)
    }
}

/// Ground control's view of the telemetry a `fireAndForget` effect sent out.
private struct TelemetryPanel: View {

    let entries: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ground control")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if entries.isEmpty {
                Text("No telemetry yet")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    Text(entry)
                        .font(.caption.monospaced())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG

    /// Previews run on immediate dependencies, so a whole flight completes without waiting.
    struct SpaceshipView_Previews: PreviewProvider {
        static var previews: some View {
            let log = TelemetryLog()
            return SpaceshipView(dependencies: .immediate(track: log.record), log: log)
        }
    }

#endif
