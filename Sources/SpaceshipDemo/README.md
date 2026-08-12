# SpaceshipDemo

A complete feature built on `CoreArchitecture`: launch a spaceship, watch it count down, ascend, and
reach orbit — or abort it mid-flight.

It exists to be read. The [root README](../../README.md) explains the pattern; this file explains where
to look for each piece of it. Nothing here is re-explained — if you want to know *why* effect bodies are
main-actor isolated, that argument lives in the root README and only there.

The demo builds and is tested with the package, so it cannot drift from the library. It is deliberately
**not** a product, so depending on the package does not expose it.

## Seeing it run

1. Open `Package.swift` in Xcode.
2. **Select the `SpaceshipDemo` scheme** — this step is not optional. Previews only run for a file the
   active scheme compiles, and the default `CoreArchitecture` scheme does not build this target.
   `CoreArchitecture-Package` works too, since it builds everything.
3. Open `SpaceshipView.swift` and show the canvas (`⌥⌘↩`).

The preview runs on `.immediate` dependencies, so a whole flight finishes without waiting. To watch it
at real speed, put `SpaceshipView()` in an app target — that initialiser wires `.live`, where the
countdown really does take a second per tick.

If the canvas reports `NoBuiltTargetDescriptionFoundForTranslationUnit`, the scheme is wrong. That error
means exactly one thing: the active scheme produced no object file for the previewed file.

For the logic alone, no UI needed:

```bash
swift test --filter SpaceshipDemoTests
```

## Read it in this order

Each file answers one question. Read them in this order and the pattern assembles itself.

| # | File | What to notice |
|---|---|---|
| 1 | `Spaceship+State.swift` | `Phase` is one enum, not a pile of booleans. There is no way to represent "counting down while already in orbit", so no view can render it. |
| 2 | `Spaceship+Action.swift` | Two `MARK` groups — pilot actions and effect actions — in **one** enum. An action carries no notion of who sent it, which is exactly what lets a test play the part of an effect. |
| 3 | `Spaceship+Dependencies.swift` | Three closures, and two wirings: `.live` waits for real, `.immediate` never waits. The reducer cannot tell which it got. Note that `wait` is a dependency — time is I/O. |
| 4 | `Spaceship+Reducer.swift` | The whole feature. Pure: every side effect leaves as an `Effect`. All five factories appear here. |
| 5 | `SpaceshipView.swift` | Owns the store, reads state, sends actions, decides nothing. The three sub-views take a state slice plus `send` and have never heard of `Store`. |
| 6 | `../../Tests/SpaceshipDemoTests/` | Both testing styles, below. |

`TelemetryLog.swift` is scaffolding rather than pattern: a visible stand-in for an analytics backend, so
the demo can *show* what `fireAndForget` does. In a real feature nothing would render it.

## Where each effect factory appears

The flight was chosen because its moments need genuinely different effect shapes — none of these is
contrived to fit.

| Factory | Flight moment | Why that shape |
|---|---|---|
| `.task` | Pre-flight checks | One async question, one answer back as `.checksCompleted`. |
| `.merge` | `launchTapped` | The action both reports and works, so it returns two effects. |
| `.fireAndForget` | Telemetry to ground control | Reaches a dependency and produces no action. Calling `deps.track` inline would cost the reducer its purity. |
| `.stream` | Countdown, then ascent | `task` emits at most one action; a countdown needs many over time. |
| `.cancel(id:)` | `abortTapped` | Tears down whichever stream is running. |

The two streams carry **separate ids** (`EffectID.countdown`, `EffectID.ascent`). That is what lets an
abort cancel them independently — and it is the flip side of the rule that effects sharing an id
replace each other.

## Testing the business logic

The tests are the point as much as the feature is. There are two styles and the choice between them is
mechanical.

**Call the reducer directly** when the claim is about a synchronous mutation, or about *whether* an
effect came back. It is a pure function, so this needs no runtime, no store, and no `await`:

```swift
let reducer = Spaceship.Reducer(deps: .immediate())
var state = Spaceship.State(phase: .ascending, altitude: 40)

let effect = reducer.reduce(&state, .launchTapped)

XCTAssertNil(effect)                        // a second launch is ignored
XCTAssertEqual(state.phase, .ascending)     // and changes nothing
```

See `test_launchTapped_whileNotGrounded_isIgnored` and `test_abort_whenGrounded_isIgnored`. Guard
clauses are the cheapest thing in the feature to get wrong and the cheapest to pin down.

**Use `TestStore`** when the claim is about the async round-trip. It runs the same reducer and the same
effect machinery as `Store`, with one deliberate difference: actions produced by effects are **queued
rather than applied**, and the test decides when to let each one in.

That is what makes `test_fullFlight_reachesOrbit` possible. A whole launch is asserted one action at a
time, and every intermediate state is observable instead of raced past:

```swift
store.send(.launchTapped)
XCTAssertEqual(store.state.phase, .runningChecks)     // synchronous, before any effect ran

await assertReceives(.checksCompleted(passed: true), on: store)
await assertReceives(.countdownTicked(secondsRemaining: 2), on: store)
await assertReceives(.countdownTicked(secondsRemaining: 1), on: store)
await assertReceives(.liftoff, on: store)
XCTAssertEqual(store.state.phase, .ascending)
```

Under a plain `Store` those intermediate phases would flash past in microseconds and the test could
only assert the final state — which would pass even if the countdown never ticked.

**Asserting on a `fireAndForget`** needs one extra step, because it produces no action to receive.
`finish()` waits for in-flight effects, then you assert on the spy — see
`test_launch_reportsTelemetryWithoutProducingAnAction`:

```swift
store.send(.launchTapped)
await store.finish()

XCTAssertEqual(log.entries, ["Launch requested"])
XCTAssertEqual(store.unconsumedActionCount, 1)   // the checks' action, deliberately not consumed
```

`unconsumedActionCount` is the assertion that catches an effect firing more often than you meant.

One deliberate omission: these tests do not re-prove that cancellation works. That is the library's
behaviour, covered in `CoreArchitectureTests`. Here, `test_abort_stopsTheFlightAndReturnsCancellation`
only checks that the reducer sets `.aborted` and returns cancellation work — the reducer's contract,
not the runtime's.

## What the demo deliberately leaves out

So it isn't mistaken for a complete template:

- **No `Coordinator`.** Navigation needs UIKit, which would make the demo iOS-only. The pattern is in
  the root README's Navigation section.
- **No repository or service layer.** All three dependencies are typed closures, which is correct for
  one-off, feature-specific operations. A collaborator shared across features would earn a protocol.
- **No real I/O.** `runPreflightChecks` returns a hard-coded answer. Swapping it for a network call
  changes nothing else, which is the point of the seam.
- **One screen, no child features.** Composition here is a sub-view taking a state slice plus `send` —
  see the root README's note on why there is no `scope` or `pullback`.
