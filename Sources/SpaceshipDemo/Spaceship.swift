import Foundation

/// Namespace for the launch feature.
///
/// A caseless `enum`, so nothing can instantiate it. Grouping `State`, `Action`, `Dependencies` and
/// `Reducer` under one name gives the feature a single entry point, and lets its own files refer to
/// `State` and `Action` without repeating the prefix.
public enum Spaceship {}
