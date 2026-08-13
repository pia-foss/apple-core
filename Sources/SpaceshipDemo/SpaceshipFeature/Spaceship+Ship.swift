import Foundation

extension Spaceship {

    /// One vessel in the fleet.
    /// `Hashable` so a `NavigationStack` path can carry whole ships rather than ids — which spares the
    /// flow from looking a ship up in state it does not own.
    public struct Ship: Hashable, Identifiable {

        /// Whether the ship can fly.
        ///
        /// Drives the pre-flight check, so it is the reason a launch can fail for reasons the pilot
        /// cannot see from the fleet screen.
        public enum Readiness: Equatable {
            case ready
            case inMaintenance
        }

        /// Stable identity, used by the fleet list.
        public let id: String

        /// The ship's display name.
        public let name: String

        /// Whether the ship can fly.
        public let readiness: Readiness

        /// Creates a ship.
        ///
        /// - Parameters:
        ///   - id: Stable identity, used by the fleet list.
        ///   - name: Display name.
        ///   - readiness: Whether the ship can fly.
        public init(id: String, name: String, readiness: Readiness) {
            self.id = id
            self.name = name
            self.readiness = readiness
        }
    }
}

extension Spaceship.Ship {

    /// The fleet the demo ships with.
    ///
    /// One vessel is in maintenance on purpose, so the failure branch is reachable by tapping rather
    /// than only from a test.
    public static let demoFleet: [Self] = [
        Self(id: "atlas", name: "Atlas", readiness: .ready),
        Self(id: "borealis", name: "Borealis", readiness: .ready),
        Self(id: "cygnus", name: "Cygnus", readiness: .inMaintenance)
    ]
}
