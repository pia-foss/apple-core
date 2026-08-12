import Foundation

extension Spaceship {

    /// Every event the feature can receive, from either screen, the navigation container, or an effect.
    ///
    /// One enum for all sources on purpose: an action carries no notion of who sent it, which is what lets
    /// a test play the part of an effect — or of a back-swipe.
    public enum Action: Equatable {

        // MARK: - Fleet screen

        case fleetAppeared
        /// The pilot picked a ship to launch.
        case shipSelected(Ship)

        // MARK: - Launch screen

        case launchTapped
        case abortTapped

        // MARK: - Navigation container

        /// The navigation stack changed, whether by a push, the back button, or a back-swipe.
        ///
        /// There is no `backTapped`: leaving is not the launch screen's decision, it is something the
        /// container reports. Routing it through the reducer is what lets a swipe-back cancel a countdown.
        case pathChanged([Ship.ID])

        // MARK: - From effects

        case fleetLoaded([Ship])
        /// Pre-flight checks finished, carrying whether they passed.
        case checksCompleted(passed: Bool)
        /// The countdown reached a new second.
        case countdownTicked(secondsRemaining: Int)
        case liftoff
        /// The ship passed a new altitude, in kilometres.
        case altitudeChanged(Int)
        case reachedOrbit
    }
}
