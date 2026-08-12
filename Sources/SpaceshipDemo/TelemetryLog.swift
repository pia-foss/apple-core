import Combine
import Foundation

/// A visible stand-in for an analytics or logging backend.
///
/// It exists so the demo can *show* what `fireAndForget` does. In a real feature this would be an
/// analytics client, and nothing would render it — which is the distinction worth noticing: telemetry
/// leaves the feature and never comes back as state.
@MainActor
public final class TelemetryLog: ObservableObject {

    /// Messages received so far, oldest first.
    @Published public private(set) var entries: [String] = []

    /// Creates an empty log.
    public init() {}

    /// Records `message` as the newest entry.
    ///
    /// - Parameter message: The telemetry line to append.
    public func record(_ message: String) {
        entries.append(message)
    }
}
