# SpaceshipDemo

Two screens and three stores. Pick a ship from the fleet, then launch it: pre-flight checks, a countdown,
ascent, orbit — or abort, or walk away mid-countdown.

It exists to be read. The [root README](../../README.md) explains the pattern; this file explains where to
look for each piece of it, and records the decisions that are not obvious from the code. Nothing is
re-explained here — if you want to know *why* effect bodies are main-actor isolated, that argument lives in
the root README and only there.

The demo builds and is tested with the package, so it cannot drift from the library.

## Seeing it run

1. Open `Package.swift` in Xcode.
2. **Select the `SpaceshipDemo` scheme.** Not optional: previews only run for a file the active scheme
   compiles, and the default `CoreArchitecture` scheme does not build this target.
   `CoreArchitecture-Package` works too, since it builds everything.
3. Open `SpaceshipFlow.swift` and show the canvas (`⌥⌘↩`).

The preview runs on **`.live`** dependencies, so the countdown really takes a second per tick and Abort is
tappable while it does. `.immediate` belongs in tests: with `wait` a no-op the whole flight finishes inside a
frame or two, so the canvas shows only the final phase and every in-flight control is disabled before you can
reach it.

If the canvas reports `NoBuiltTargetDescriptionFoundForTranslationUnit`, the scheme is wrong. That error means
exactly one thing: the active scheme produced no object file for the previewed file.

For the logic alone:

```bash
swift test --filter SpaceshipDemoTests
```

## Three stores, and the rule that puts them there

| Store | Owned by | Holds | Actions |
|---|---|---|---|
| `Flow` | `SpaceshipFlow` | navigation path, each ship's last result | 3 |
| `Fleet` | `FleetScreen` | the ship list, loading flag | 2 |
| `Launch` | `LaunchScreen` | one ship, one attempt | 7 |

Every screen owns exactly one store and creates it itself. None of them is handed a `send` closure.

The rule that decides where a store lives:

> **A store can only receive from code that can see it.**

Two facts in this demo are produced by one screen and rendered by another — the navigation path, and a
launch's result. Neither belongs to either screen, so putting them in either one gives that screen a
privileged position and forces the other to be fed slices. Giving coordination its own store removes the
privilege, and `Flow` stays small: three actions, one dependency, no cancellation, no loading.

Communication runs one way in each direction, and never screen-to-screen:

```
                    ┌──────────── SpaceshipFlow ────────────┐
                    │            (Flow store)               │
                    │  path · results                       │
                    └───┬───────────────────────────────┬───┘
         results down    │                             │    seeded phase down
         onSelect up     │                             │    reportResult up
                    ┌───▼──────────┐            ┌──────▼───────┐
                    │  FleetScreen │            │ LaunchScreen │
                    │ (Fleet store)│            │(Launch store)│
                    └──────────────┘            └──────────────┘
```

`FleetScreen` reports `onSelect(ship)` without knowing it pushes anything. `LaunchScreen` reports through its
`reportResult` dependency without knowing a fleet exists. `SpaceshipFlow` is the only place that knows both.

## The state machine

`Launch` is the only feature with a real machine. `Flow` and `Fleet` are a stack and a list.

```
grounded ──launchTapped──▶ runningChecks
   ▲                             │
   │              ┌──────────────┴──────────────┐
   │              ▼                             ▼
   │        checksFailed              countdown(3…1)
   │                                            │
   │                                         liftoff
   │                                            ▼
   │                              ascending ──────▶ inOrbit
   │                                    │
   └──────────── abortTapped ───────────┘
```

- **Aborting undoes the launch.** It returns the ship to `grounded` rather than becoming a terminal state of
  its own, which is why there is no `.aborted` phase to explain.
- **A terminal phase is not a dead end.** `launchTapped` guards on `!phase.isInFlight`, not `== .grounded`,
  so a ship that reached orbit or failed its checks can try again.
- **Only final phases go upward.** `isFinal` gates the report, so walking away mid-countdown leaves the
  recorded result untouched rather than freezing it on a countdown nothing is running.

### Leaving a screen needs no cleanup

`Flow.Reducer.navigate` returns no effect at all. The launch store belongs to the pushed screen, so popping
releases it and `Store.deinit` cancels whatever it had running.

That is the strongest practical argument for a store per screen, and it was not free before: an earlier
single-store version had to walk the departed ships and ground each one by hand, or the fleet row would claim
a countdown that nothing was running. `test_poppingTheStack_needsNoCleanup` pins the current behaviour.

## Read it in this order

Two folders. `SpaceshipFeature/` holds everything a second app could reuse; `SpaceshipUI/` holds the views.

**`SpaceshipFeature/`** — no SwiftUI:

| # | File | What to notice |
|---|---|---|
| 1 | `Spaceship+Ship.swift` | Shared domain. One ship is `inMaintenance`, so the checks-failed branch is reachable by tapping, not only from a test. `Hashable` so the navigation path can carry whole ships. |
| 2 | `Spaceship+Phase.swift` | Shared domain, because `Launch` moves a ship through these and `Flow` remembers the last one. One enum, not a pile of booleans: "counting down while already in orbit" is unrepresentable. |
| 3 | `Flow/Flow.swift`, `Flow+Reducer.swift` | Coordination. Three actions, all arriving from outside itself: a screen's output, the navigation container, another feature. |
| 4 | `Fleet/Fleet.swift`, `Fleet+Reducer.swift` | The smallest feature — load a list, show it. No `shipSelected`: the screen reports that, and `Flow` decides what it means. |
| 5 | `Fleet/FleetRepository.swift`, `Launch/LaunchService.swift` | Protocols with named implementations. This is where logic lives — not in the wiring, and not in a closure. |
| 6 | `Launch/Launch.swift` | Four dependencies, each one this feature actually uses. `wait` is one of them: time is I/O. |
| 7 | `Launch/Launch+Reducer.swift` | `reduce` is a routing table, one line per action, with a named handler below for each transition. All five effect factories appear here. |

**`SpaceshipUI/`** — SwiftUI only:

| # | File | What to notice |
|---|---|---|
| 8 | `FleetScreen.swift`, `LaunchScreen.swift` | Each creates its own store in `init`. Each reports outward and decides nothing. Both preview without a flow. |
| 9 | `SpaceshipFlow.swift` | Not a screen — it renders none of its own. Owns the `Flow` store, binds the `NavigationStack` path to it, and builds each `LaunchScreen`. |
| 10 | `DemoStyle.swift` | Presentation values for the domain enums, kept in the UI folder so the feature layer never imports SwiftUI. |
| 11 | `../../Tests/SpaceshipDemoTests/` | One file per store, below. |

`TelemetryLog.swift` is scaffolding rather than pattern: a visible stand-in for an analytics backend, so the
demo can *show* what `fireAndForget` does. In a real feature nothing would render it — and note that no
feature knows it exists, because `track` is a closure the flow supplies.

## Naming

Three kinds of view, and the suffix says which:

- **`*Screen`** — a full screen. `FleetScreen`, `LaunchScreen`.
- **`*View`** — a component inside a screen. `ShipRowView`, `PhaseBadgeView`, `AltitudeBarView`,
  `TelemetryPanelView`.
- **`*Flow`** — the feature's root. Owns coordination, composes screens, renders no screen of its own.
  `SpaceshipFlow`.

The third exists because the root is neither. It was briefly called `SpaceshipScreen`, which claimed two
screens where the user sees one.

Bindings are named for the type they are, not the concept they relate to: `fleetStore`, `fleetRepository`,
`launchService` — never bare `fleet`. `state.fleet` would be a list of ships, and a short name reads as the
wrong type at the call site.

## On layering

`SpaceshipFeature/` and `SpaceshipUI/` are the two layers the pattern separates: logic that could be shared
across apps, and the views of one. In a real project they would be separate SPM targets, and the split would
be worth it — a target boundary makes the dependency direction a **build error**, so a reducer could not
reference a view even by accident.

Here they are folders in one target, which keeps the demo to a single scheme. The cost is real: nothing stops
a view and a reducer referencing each other, so the layering holds by convention and review rather than by
the compiler.

That distinction is not academic. While these were briefly two targets, the build immediately caught the
feature tests borrowing `TelemetryLog` — a UI type — as a telemetry spy. They now hand-roll their own `Spy`,
which is what the project's no-mocking-framework rule asks for anyway.

## On navigation: a router, not a coordinator

The path lives in `Flow.State` and a real `NavigationStack` binds to it:

```swift
NavigationStack(path: flowStore.binding(\.path) { .pathChanged($0) }) { … }
```

That is why there is no `backTapped` action. The nav bar's back button and the back-swipe gesture never call
into a feature — they change the stack, `store.binding` turns that into `.pathChanged`, and the reducer gets
to react. A gesture the feature cannot see is how a hand-rolled architecture ends up with a stream ticking
into a screen nobody is looking at.

**The demo deliberately does not use the library's `Coordinator` protocol.** That protocol is the UIKit
contract — `AnyObject` plus `start()` — and it is shaped that way because a UIKit coordinator has to
imperatively push a first view controller. A SwiftUI `View` is a struct and is never "started", so conforming
would be ceremony. Where navigation is fully declarative, the coordinator's job is done by state, and this
demo is that case.

The two are not rivals: a coordinator is what you reach for while root navigation is still UIKit-hosted, and
a router is where it lands once the stack itself is declarative.

What the demo keeps either way is the principle, which is the same in both: **a screen never knows what comes
next.** Screens expose output closures and the layer above decides.

Showing the coordinator path properly needs a UIKit host and a `UIHostingController` bridge, which would make
the demo iOS-only. That belongs in a separate demo.

## Where each effect factory appears

| Factory | Where | Why that shape |
|---|---|---|
| `.task` | `Fleet` load, `Launch` pre-flight checks | One async question, one answer back as an action. |
| `.merge` | `Launch` begin, abort, ascend | Those actions each both report and work, so each returns two effects. |
| `.fireAndForget` | telemetry everywhere, and `reportResult` | Reaches a dependency and produces no action. Calling one inline in `reduce` would cost the reducer its purity. |
| `.stream` | countdown, then ascent | `task` emits at most one action; a countdown needs many over time. |
| `.cancel(id:)` | `Launch.abortTapped` | Tears down whichever stream is running. |

The two streams carry **separate ids** (`EffectID.countdown`, `EffectID.ascent`), which is what lets an abort
cancel them independently — the flip side of the rule that effects sharing an id replace each other.

## Testing the business logic

One test file per store, and the clearest evidence the decomposition is right is what each file *cannot*
mention. `FleetReducerTests` has no navigation, no results, no countdown. `FlowReducerTests` has no loading
and no altitude. `LaunchReducerTests` constructs one ship with no dictionary to index.

There are two styles, and the choice between them is mechanical.

**Call the reducer directly** when the claim is about a synchronous mutation, a navigation transition, or
*whether* an effect came back. It is a pure function, so this needs no runtime, no store, and no `await`:

```swift
var state = Flow.State()

let effect = makeReducer().reduce(&state, .shipSelected(atlas))

XCTAssertEqual(state.path, [atlas])
XCTAssertNotNil(effect)                  // telemetry
```

Navigation being state is what makes that possible — no view, no window, no navigation controller. The same
style pins the guards down, and guards are the cheapest thing in a state machine to get wrong:
`test_selectingShip_whileAlreadyPushed_isIgnored`, `test_launch_whileAlreadyFlying_isIgnored`,
`test_abort_whileGrounded_isIgnored`, `test_appeared_afterLoading_doesNotRefetch`.

**Use `TestStore`** when the claim is about the async round-trip. It runs the same reducer and the same effect
machinery as `Store`, with one deliberate difference: actions produced by effects are **queued rather than
applied**, and the test decides when to let each one in.

That is what makes `test_fullFlight_reachesOrbit` possible — a whole launch asserted one action at a time,
with every intermediate phase observable instead of raced past:

```swift
store.send(.launchTapped)
XCTAssertEqual(store.state.phase, .runningChecks)     // synchronous, before any effect ran

await assertReceives(.checksCompleted(passed: true), on: store)
await assertReceives(.countdownTicked(secondsRemaining: 2), on: store)
await assertReceives(.countdownTicked(secondsRemaining: 1), on: store)
await assertReceives(.liftoff, on: store)
XCTAssertEqual(store.state.phase, .ascending)
```

Under a plain `Store` those phases would flash past in microseconds, so a test could only assert the final
state — and would still pass if the countdown never ticked.

**Asserting on a `fireAndForget`** needs one extra step, because it produces no action to receive. `finish()`
waits for in-flight effects, then you assert on the spy:

```swift
store.send(.reachedOrbit)
await store.finish()

XCTAssertEqual(spy.results, [.inOrbit])
XCTAssertEqual(spy.telemetry, ["Orbit reached"])
```

That is also how the cross-feature handoff is tested. `reportResult` is a dependency, so
`test_reachingOrbit_reportsTheResult` asserts on a spy exactly as telemetry does — and
`test_abort_reportsNoResult` proves an interrupted flight reports nothing. In the app the flow wires the same
closure to `Flow.Action.flightFinished`.

`unconsumedActionCount` catches an effect that fired more often than you meant. Fakes are hand-rolled; there
is no mocking framework here by choice.

One deliberate omission: these tests do not re-prove that cancellation works. That is the library's
behaviour, covered in `CoreArchitectureTests`. Here a reducer test only checks that the right action returns
cancellation work — the reducer's contract, not the runtime's.

## What the demo deliberately leaves out

So it isn't mistaken for a complete template:

- **No `Coordinator`.** See *On navigation* above. It needs a UIKit host, which would make the demo iOS-only.
- **No error states.** `FleetRepository.all()` cannot fail. A repository that throws would add a loading-error
  branch to `Fleet.State` — realistic, and beside the point being made here.
- **No real I/O.** The repository returns a literal and the service reads a flag. Swapping either for a
  network call changes nothing else, which is the point of the seam.
- **No child features below a screen.** Composition inside a screen is a sub-view taking a state slice plus
  plain values — see the root README on why there is no `scope` or `pullback`.
- **`Store` is not `Sendable`-hardened.** The package is Swift 5 language mode; strict-concurrency adoption is
  open work in the library, not the demo.
