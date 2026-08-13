import Foundation

@testable import SpaceshipDemo

/// Records telemetry and reported results so tests can assert what a reducer sent outward.
///
/// Hand-rolled rather than borrowed from the UI folder: these tests cover the feature layer, and there is
/// no mocking framework here by choice.
@MainActor
final class Spy {

    private(set) var telemetry: [String] = []
    private(set) var results: [Spaceship.Phase] = []

    func track(_ message: String) {
        telemetry.append(message)
    }

    func report(_ phase: Spaceship.Phase) {
        results.append(phase)
    }
}
