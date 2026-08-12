import Foundation

extension Spaceship {

    /// Every event the launch feature can receive, from the pilot or from an effect.
    ///
    /// Both sources share one enum on purpose: an action carries no notion of who sent it, which is
    /// what lets a test drive an effect's output by hand.
    public enum Action: Equatable {

        // MARK: - From the pilot

        case launchTapped
        case abortTapped
        case resetTapped

        // MARK: - From effects

        /// Pre-flight checks finished, carrying whether they passed.
        case checksCompleted(passed: Bool)
        /// The countdown reached a new second.
        case countdownTicked(secondsRemaining: Int)
        case liftoff
        /// The spaceship passed a new altitude, in kilometres.
        case altitudeChanged(Int)
        case reachedOrbit
    }
}
