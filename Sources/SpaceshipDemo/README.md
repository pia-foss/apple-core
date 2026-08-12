# SpaceshipDemo

A two-screen feature built on `CoreArchitecture`. Pick a ship from the fleet, then launch it: pre-flight
checks, a countdown, ascent, orbit — or abort, or walk away mid-countdown.

It exists to be read. The [root README](../../README.md) explains the pattern; this file explains where
to look for each piece of it. Nothing here is re-explained — if you want to know *why* effect bodies are
main-actor isolated, that argument lives in the root README and only there.

The demo builds and is tested with the package, so it cannot drift from the library.

## The state machine

Two nested machines, and the reducer is the only thing that moves either.

```
path  ─── []  ──shipSelected──▶ [ship.id] ──pathChanged([])──▶ []

Flight.Phase ─ grounded ──launchTapped──▶ runningChecks
                  ▲                             │
                  │              ┌──────────────┴──────────────┐
                  │              ▼                             ▼
                  │        checksFailed              countdown(3…1)
                  │                                            │
                  │                                         liftoff
                  │                                            ▼
                  │                              ascending ──────▶ inOrbit
                  │                                    │
                  └──── abortTapped / pathChanged ─────┘
```

Three things this shape buys, all visible in the tests:

- **One flight per ship, in `State.flights`.** Both screens read the same value, so they cannot disagree
  about what a ship is doing. Reopening a ship shows the phase the fleet row just showed.
- **Navigation is state.** Which screen shows is a value the reducer sets, so "selecting a ship opens
  the launch screen" is a plain unit test with no view, window, or navigation controller involved.
- **Aborting undoes the launch.** It returns the ship to `grounded` rather than becoming a terminal state
  of its own, which is why there is no `.aborted` phase to explain.

Two consequences worth noticing:

- **Leaving mid-flight resets too.** Popping cancels the effects, so without a reset the stored
  phase would stay frozen on `.countdown(2)` and the fleet row would claim a countdown that nothing is
  running. Terminal phases are left alone, so orbit survives leaving the screen.
- **A terminal phase is not a dead end.** `launchTapped` guards on `!phase.isInFlight`, not
  `== .grounded`, so a ship that reached orbit or failed its checks can try again.

> **This is the second design.** The first kept the `Flight` inside a single-route enum and a separate
> `Outcome` in a parallel dictionary — two representations of one fact. Reopening a ship built a fresh
> grounded flight while the fleet row still read "in orbit", and the two screens disagreed. The fix was
> not to sync them but to delete one of them. `test_reopeningAShip_showsThePhaseTheFleetShowed` holds the
> line.

`Spaceship.State.flight` is a computed accessor over `path` and `flights`, so the reducer can write
`state.flight?.phase = .ascending` without reaching through the path into the dictionary by hand.
`State.launching(_:)` builds a state already on the launch screen, which is what the tests use.

## Seeing it run

1. Open `Package.swift` in Xcode.
2. **Select the `SpaceshipDemo` scheme** — this step is not optional. Previews only run for a file the
   active scheme compiles, and the default `CoreArchitecture` scheme does not build this target.
   `CoreArchitecture-Package` works too, since it builds everything.
3. Open `SpaceshipView.swift` and show the canvas (`⌥⌘↩`).

The preview runs on **`.live`** dependencies, so the countdown really does take a second per tick and the
Abort button is tappable while it does.

`.immediate` belongs in tests, not the canvas. With `wait` a no-op the whole flight — checks, three
countdown ticks, five altitude steps, orbit — completes inside a frame or two, so the canvas shows only
the final phase and every in-flight control is disabled before you can reach it.

If the canvas reports `NoBuiltTargetDescriptionFoundForTranslationUnit`, the scheme is wrong. That error
means exactly one thing: the active scheme produced no object file for the previewed file.

For the logic alone, no UI needed:

```bash
swift test --filter SpaceshipDemoTests
```

## Read it in this order

Each file answers one question. Two folders, and the order runs through both. `SpaceshipFeature/` holds everything a second app could
reuse; `SpaceshipUI/` holds the views.

**`SpaceshipFeature/`** — no SwiftUI:

| # | File | What to notice |
|---|---|---|
| 1 | `Spaceship+Ship.swift` | The domain model. One ship is `inMaintenance`, so the checks-failed branch is reachable by tapping, not only from a test. |
| 2 | `Spaceship+Flight.swift` | `Phase` is one enum, not a pile of booleans. "Counting down while already in orbit" is unrepresentable, so no view can render it. |
| 3 | `Spaceship+State.swift` | `path` is the navigation stack and `flights` holds one flight per ship. `flight` is a computed accessor over both, so a ship's phase has exactly one home. |
| 4 | `Spaceship+Action.swift` | Four `MARK` groups — fleet screen, launch screen, navigation container, effects — in **one** enum. An action carries no notion of who sent it, which is what lets a test play the part of an effect, or of a back-swipe. |
| 5 | `FleetRepository.swift`, `LaunchService.swift` | Protocols with named implementations. This is where logic lives — not in the wiring, and not in a closure. |
| 6 | `Spaceship+Dependencies.swift` | Two protocols and two closures, following ADR 0010's composition rule. `.live` and `.immediate` only *assemble* components; neither holds behaviour. |
| 7 | `Spaceship+Reducer.swift` | The whole feature. Every branch guards on the phase or path it needs, so an action arriving in the wrong state is ignored rather than corrupting the machine. |

**`SpaceshipUI/`** — SwiftUI only:

| # | File | What to notice |
|---|---|---|
| 8 | `FleetView.swift`, `LaunchView.swift` | Two actions each. Both take a state slice plus `send` and have never heard of `Store`, so both preview from a literal. |
| 9 | `SpaceshipView.swift` | Owns the store and binds a `NavigationStack` path straight to state. |
| 10 | `DemoStyle.swift` | Presentation values for the feature's enums, kept out of the feature target so the state layer stays UI-free. |
| 11 | `../../Tests/SpaceshipDemoTests/` | Both testing styles, below. |

`TelemetryLog.swift` is scaffolding rather than pattern: a visible stand-in for an analytics backend, so
the demo can *show* what `fireAndForget` does. In a real feature nothing would render it. Note that it
lives in the UI target and the feature layer never sees it — `.live(track:)` takes a closure, so nothing
in `SpaceshipFeature` knows what displays telemetry.

## On layering

`SpaceshipFeature/` and `SpaceshipUI/` are the two layers ADR 0010 separates: shared logic and per-app
views. In a real project they would be separate SPM targets, and the split would be worth it — a target
boundary makes the dependency direction a **build error**, so a reducer could not reference a view even by
accident.

Here they are folders in one target, which keeps the demo to a single scheme. Be honest about the cost:
nothing stops a view and a reducer referencing each other, so the layering holds by convention and review
rather than by the compiler.

The distinction is not academic. While these were briefly two targets, the build immediately caught the
feature tests borrowing `TelemetryLog` — a UI type — as a telemetry spy. They now hand-roll their own
`TelemetrySpy`, which is what the project's no-mocking-framework rule asks for anyway, and it stays that
way because reaching across the boundary was the wrong instinct regardless of whether a compiler says so.

## On navigation

The path lives in state and a real `NavigationStack` binds to it:

```swift
NavigationStack(path: store.binding(\.path) { .pathChanged($0) }) { … }
```

That is the whole trick, and it is why there is no `backTapped` action. The nav bar's back button and the
back-swipe gesture never call into the feature — they change the stack, `store.binding` turns that into
`.pathChanged`, and the reducer gets to cancel the running countdown. A gesture the feature cannot see is
exactly how a hand-rolled architecture ends up with a stream ticking into a screen nobody is looking at.
`test_aSwipeBackCancelsARunningCountdown` holds that line.

Two things this is not:

- **Not a `Coordinator`.** Cross-*feature* navigation is what ADR 0009's coordinators own, and that path
  needs `UINavigationController` and `UIHostingController` — iOS-only, so a cross-platform demo cannot
  show it. Within one feature, screen state is just state.
- **Not available at the library's floor.** `NavigationStack` is iOS 16, so `SpaceshipView` carries an
  `@available` attribute. `CoreArchitecture` itself still supports iOS 15.

## Where each effect factory appears

The flight was chosen because its moments need genuinely different effect shapes — none of these is
contrived to fit.

| Factory | Flight moment | Why that shape |
|---|---|---|
| `.task` | Pre-flight checks | One async question, one answer back as `.checksCompleted`. |
| `.merge` | `launchTapped` | The action both reports and works, so it returns two effects. |
| `.fireAndForget` | Telemetry to ground control | Reaches a dependency and produces no action. Calling `deps.track` inline would cost the reducer its purity. |
| `.stream` | Countdown, then ascent | `task` emits at most one action; a countdown needs many over time. |
| `.cancel(id:)` | `abortTapped` **and** `pathChanged` | Tears down whichever stream is running. |

The two streams carry **separate ids** (`EffectID.countdown`, `EffectID.ascent`). That is what lets an
abort cancel them independently — and it is the flip side of the rule that effects sharing an id
replace each other.

`pathChanged` is the case worth studying. Leaving a screen is a navigation change *and* a cleanup: without
the cancellation, a countdown keeps ticking into a screen nobody is looking at, and the store keeps
applying its actions to a route that no longer holds a flight.

## Testing the business logic

The tests are the point as much as the feature is. There are two styles and the choice between them is
mechanical.

**Call the reducer directly** when the claim is about a synchronous mutation, a navigation transition, or
*whether* an effect came back. It is a pure function, so this needs no runtime, no store, and no `await`.

Navigation being state is what makes this possible — no view, no window, no navigation controller:

```swift
var state = Spaceship.State(fleet: [atlas])

let effect = makeReducer().reduce(&state, .shipSelected(atlas))

XCTAssertEqual(state.path, [atlas.id])
XCTAssertEqual(state.flight?.phase, .grounded)
```

The same style pins the guards down, and guards are the cheapest thing in a state machine to get wrong:

```swift
var state = Spaceship.State(fleet: [atlas])                  // on the fleet screen

XCTAssertNil(makeReducer().reduce(&state, .launchTapped))    // nothing to launch
XCTAssertEqual(state.path, [])
```

See `test_launch_whileOnFleetScreen_isIgnored`, `test_launch_whileAlreadyFlying_isIgnored`,
`test_abort_whileGrounded_isIgnored` and `test_fleetLoadsOnce`.

Two tests hold a distinction the machine must not blur:
`test_abort_returnsTheShipToGroundedAndStaysOnTheStack` and
`test_poppingTheStack_returnsToFleetAndCancelsTheFlight`. Both cancel effects and both ground the ship; only one
changes the route.

Three more cover what survives leaving a screen and what does not:
`test_reopeningAShip_showsThePhaseTheFleetShowed`, `test_poppingMidFlight_leavesTheShipGrounded` and
`test_poppingFromATerminalPhase_keepsIt`.

**Use `TestStore`** when the claim is about the async round-trip. It runs the same reducer and the same
effect machinery as `Store`, with one deliberate difference: actions produced by effects are **queued
rather than applied**, and the test decides when to let each one in.

That is what makes `test_fullFlight_reachesOrbit` possible. A whole launch is asserted one action at a
time, and every intermediate state is observable instead of raced past:

```swift
store.send(.launchTapped)
XCTAssertEqual(store.state.flight?.phase, .runningChecks)   // synchronous, before any effect ran

await assertReceives(.checksCompleted(passed: true), on: store)
await assertReceives(.countdownTicked(secondsRemaining: 2), on: store)
await assertReceives(.countdownTicked(secondsRemaining: 1), on: store)
await assertReceives(.liftoff, on: store)
XCTAssertEqual(store.state.flight?.phase, .ascending)
```

Under a plain `Store` those intermediate phases would flash past in microseconds and the test could
only assert the final state — which would pass even if the countdown never ticked.

**Asserting on a `fireAndForget`** needs one extra step, because it produces no action to receive.
`finish()` waits for in-flight effects, then you assert on the spy — see
`test_launch_reportsTelemetryWithoutProducingAnAction`:

```swift
store.send(.launchTapped)
await store.finish()

XCTAssertEqual(log.entries, ["Launch requested: Atlas"])
XCTAssertEqual(store.unconsumedActionCount, 1)   // the checks' action, deliberately not consumed
```

`unconsumedActionCount` is the assertion that catches an effect firing more often than you meant.

One deliberate omission: these tests do not re-prove that cancellation works. That is the library's
behaviour, covered in `CoreArchitectureTests`. Here the reducer tests check only that the right actions
return cancellation work — the reducer's contract, not the runtime's.

## What the demo deliberately leaves out

So it isn't mistaken for a complete template:

- **No `Coordinator`.** Cross-feature navigation needs UIKit, which would make the demo iOS-only. See
  the "On navigation" section above and the root README's Navigation section.
- **No `NavigationStack`.** The route is state and the root view switches on it, which keeps the demo
  buildable at the library's iOS 15 floor and keeps navigation unit-testable.
- **No repository or service layer.** All four dependencies are typed closures, which is correct for
  one-off, feature-specific operations. A collaborator shared across features would earn a protocol.
- **No real I/O.** `loadFleet` returns a literal and `runPreflightChecks` reads a flag. Swapping either
  for a network call changes nothing else, which is the point of the seam.
- **No child features.** Composition here is a sub-view taking a state slice plus `send` — see the root
  README's note on why there is no `scope` or `pullback`.
