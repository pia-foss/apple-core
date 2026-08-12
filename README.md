# CoreArchitecture

The primitives for the unidirectional-MVI architecture defined in **ADR 0010**, plus the navigation
contract from **ADR 0009**. UI-agnostic and dependency-free, so it is the shared Apple-platform
foundation for both **CyberGhost and PIA**: `State` / `Action` / `Reducer` / `Dependencies` live in
shared packages, and only SwiftUI views and `.live` wiring are per-app.

The ADRs are the authority. This README is how to use what they decided.

> **Reference implementation:** [`Shared/WelcomeBackFeature`](../WelcomeBackFeature) — a complete
> feature built on these primitives, with reducer tests. Read it alongside this file.

---

## The loop

*State flows down, actions flow up.*

```
State ──renders──▶ View ──emits──▶ Action
  ▲                                   │
  │ new State                         │ store.send(action)
  └────── reduce(&state, action) ◀────┘
                │
                └─ Effect ──async (injected Dependencies)──▶ Action′
```

Three invariants. They are not style preferences — every guarantee the pattern offers rests on them:

1. **`state` is read-only to views.** The only mutation path is `store.send(_:)`.
2. **`reduce` is pure.** No I/O, no singletons, deterministic given its inputs.
3. **All impurity lives behind injected `Dependencies`** and runs only inside `Effect`s.

## What ships here

| Type | Role |
|---|---|
| `Store<State, Action>` | `@MainActor ObservableObject`. Holds state, runs `send`, executes effects, feeds their actions back. |
| `Effect<Action>` | A description of async work a reducer returns. Cancellable by id. |
| `TestStore<State, Action>` | Deterministic test driver. Same effect machinery, but effect output is queued for the test to consume. `DEBUG`-only. |
| `Coordinator` | The ADR 0009 navigation contract: `func start()`. |

`State`, `Action`, `Reducer` and `Dependencies` are **not** here — they are per-feature types that
live in the feature's own package. This package only provides what they plug into.

## Writing a feature

Five types. `State` and `Action` are plain values:

```swift
public struct ItemState: Equatable {
    public var items: [Item] = []
    public var isLoading = false
}

public enum ItemAction: Equatable {
    case onAppear
    case itemsLoaded([Item])
    case refreshTapped
}
```

`Dependencies` is a struct of the collaborators that keep the reducer pure. Protocols for
Repositories and Services (shared, navigable); typed closures for feature-specific one-offs:

```swift
public struct ItemDependencies {
    public var items: any ItemRepository          // protocol: shared across features
    public var track: (AnalyticsEvent) -> Void    // closure: one-off, no protocol needed
}
```

`Reducer` is a struct that captures its dependencies at init and mutates state in exactly one place:

```swift
public struct ItemReducer {
    public let deps: ItemDependencies

    public func reduce(_ state: inout ItemState, _ action: ItemAction) -> Effect<ItemAction>? {
        switch action {
        case .onAppear:
            state.isLoading = true
            return .task { [deps] in .itemsLoaded((try? await deps.items.getItems()) ?? []) }

        case .itemsLoaded(let items):
            state.isLoading = false
            state.items = items
            return nil

        case .refreshTapped:
            // Analytics is I/O, so it goes out as an effect rather than being called inline —
            // that is what keeps `reduce` pure. `merge` runs both.
            return .merge(
                .fireAndForget { [deps] in deps.track(.refreshTapped) },
                .task { [deps] in .itemsLoaded((try? await deps.items.getItems()) ?? []) }
            )
        }
    }
}
```

The view owns the store, reads state, and sends actions. Sub-views take a state slice plus a `send`
closure as plain arguments — they never know a `Store` exists:

```swift
struct ItemView: View {
    @StateObject var store: Store<ItemState, ItemAction>

    var body: some View {
        List(store.state.items) { item in
            ItemRow(item: item, send: store.send)
        }
        .task { store.send(.onAppear) }
    }
}
```

`Dependencies` gets two wirings. `.live` belongs in the app (it is allowed to know about
singletons); the reducer never sees which side it is on:

```swift
extension ItemDependencies {
    static var live: Self {
        .init(
            items: DefaultItemRepository(),
            track: { AnalyticsManager.shared.track($0) }
        )
    }
}
```

## Effects

| Factory | Use for | Emits |
|---|---|---|
| `.task(id:_:)` | A fetch, a submit, a purchase | one action, or none |
| `.fireAndForget(id:_:)` | Analytics, logging, a persist | nothing |
| `.stream(id:_:)` | Engine observation, timers, retry loops | many actions over time |
| `.merge(_:)` | Several of the above at once | whatever they emit |
| `.cancel(id:)` | Tearing down in-flight work | nothing |

Returning `nil` from `reduce` means "no effect".

**Isolation.** Effect bodies are `@MainActor`. This is deliberate: a `Dependencies` closure here
usually wraps an existing singleton (`VPNManager.shared`, `AnalyticsManager.shared`) that is not
thread-safe, and a non-isolated body would call it from the global executor. `await deps.fetch()`
still releases the main thread — the network or engine work runs wherever its implementation runs —
so only the glue stays on the main actor. An effect that genuinely needs to burn CPU should hop off
explicitly rather than assume it may.

**Cancellation.** An effect with an `id` is tracked and can be torn down with `.cancel(id:)`. The
rule to remember: **the same `id` means one at a time — starting a new effect under an `id` cancels
whatever was already in flight under it.** That is what debouncing, reconnect timers and
re-subscription want. Effects that must genuinely run concurrently need distinct ids, or none.

Cancellation is cooperative, as everywhere in Swift concurrency: the `Task` is cancelled, and the
body notices by `await`ing something that throws, checking `Task.isCancelled`, or iterating an
`AsyncSequence` that ends on cancellation. Anything still in flight is cancelled when the `Store` is
released, so a `.stream` does not outlive its screen.

```swift
private enum EffectID { case vpnStatus }

case .onAppear:
    return .stream(id: EffectID.vpnStatus) { [deps] send in
        for await status in deps.vpnStatusUpdates() {
            send(.statusChanged(status))
        }
    }

case .disconnectTapped:
    return .merge(
        .cancel(id: EffectID.vpnStatus),
        .task { [deps] in await deps.disconnect(); return .disconnected }
    )
```

`.stream` requires an `id` rather than defaulting it: a stream nobody can cancel runs until the whole
store is torn down, which for a reconnect loop is a leak rather than a shortcut.

## Testing

A reducer is a pure function, so the cheapest test calls it directly — no runtime, no device. Use
this when the claim is about the synchronous mutation or about *whether* an effect was returned:

```swift
var state = ItemState()
let effect = ItemReducer(deps: .test).reduce(&state, .onAppear)

XCTAssertTrue(state.isLoading)
XCTAssertNotNil(effect)
```

Use `TestStore` when the claim is about the async round-trip. It runs the same reducer and the same
effect machinery as `Store` — so cancellation and merging behave identically — with one deliberate
difference: **actions produced by effects are queued rather than applied**, and the test decides when
to let them in. That is what makes the round-trip assertable instead of raced.

```swift
@MainActor
func test_load() async {
    let spy = Spy()
    let store = TestStore(
        initial: ItemState(),
        reduce: ItemReducer(deps: .init(items: FakeRepository(), track: spy.track)).reduce
    )

    store.send(.onAppear)
    XCTAssertTrue(store.state.isLoading)          // synchronous mutation

    let received = await store.receive()          // the effect's action, then applied
    XCTAssertEqual(received, .itemsLoaded([.fixture]))
    XCTAssertFalse(store.state.isLoading)

    await store.finish()                          // drain fire-and-forget work
    XCTAssertEqual(spy.events, [.refreshTapped])
    XCTAssertEqual(store.unconsumedActionCount, 0)
}
```

- `receive(timeout:)` returns `nil` on timeout — assert non-`nil` for a readable failure. It takes no
  XCTest dependency, so it works from Swift Testing too.
- `finish(timeout:)` waits for in-flight effects, then cancels what is left (a `.stream` never ends on
  its own). Use it before asserting on a spy that a fire-and-forget effect writes to.
- `unconsumedActionCount` catches an effect that fired more times than expected.

Fakes are hand-rolled, per the project's no-mocking-framework rule.

## Navigation

`Coordinator` is the whole contract: `func start()`. **A screen never knows what comes next.** Views
and view controllers hold no coordinator reference — they expose output closures the coordinator
injects, and the coordinator decides the transition. UIKit and SwiftUI use the identical pattern; the
`UIHostingController` wrap is a coordinator detail.

The `Store` owns state; the coordinator owns transitions. A coordinator starts an MVI feature by
creating its `Store` and handing it to the feature view — that is the entire seam between ADR 0010
and ADR 0009, and the reason the protocol ships here rather than in an app target. Conformers
`import CoreArchitecture`:
[`AppCoordinator`](../../iOS/CyberGhost%207/App/CyberGhost%206v2%20main/Navigation/AppCoordinator.swift)
(the root — owns the window and installs the shell),
[`MainCoordinator`](../../iOS/CyberGhost%207/App/CyberGhost%206v2%20main/MainCoordinator.swift), and
[`WelcomeBackCoordinator`](../../iOS/CyberGhost%207/App/CyberGhost%206v2%20main/Features/WelcomeBack/WelcomeBackCoordinator.swift)
(the first flow built to this pattern end to end).

`childCoordinator` and `cancellables` are deliberately not protocol requirements — they belong to
coordinators that happen to own child flows or use Combine, and Swift protocols cannot supply stored
properties anyway. ADR 0009 reserves an opt-in `ParentCoordinator` for the day several coordinators
genuinely need to declare child ownership.

## Review checklist

Nothing in the build system enforces these. Review is the gate.

**State and logic**
- [ ] `State` is a value type and `Equatable`; views only read it.
- [ ] Every mutation goes through `store.send(_:)` — no `NotificationCenter`, no singleton writes.
- [ ] `reduce` is pure: no I/O, no `.shared`. **If `.shared` appears in a reducer, that dependency
      belongs in `Dependencies`.**
- [ ] Analytics, logging and persistence go out as `.fireAndForget`, not inline calls in `reduce`.
- [ ] `Dependencies` has both a `.live` and a test wiring; `.live` is the only place that knows about
      singletons.

**Effects**
- [ ] Every long-lived effect has an `id` and something cancels it.
- [ ] Two effects sharing an `id` are meant to replace each other — not meant to run concurrently.
- [ ] Effect bodies observe cancellation (`try await`, `Task.isCancelled`, or an `AsyncSequence`).

**Navigation**
- [ ] The screen exposes output closures; it holds no coordinator reference and decides nothing.
- [ ] Every injected closure captures `self` as `weak`.
- [ ] Every subscription is stored in `cancellables` — one that is not is cancelled immediately and
      silently.
- [ ] `cancellables.removeAll()` runs before a child coordinator is replaced.
- [ ] Data reaches the next flow through the child coordinator's `init`, not shared state.

**Structure**
- [ ] The `State` / `Action` / `Reducer` / `Dependencies` layer is in a shared SPM package (CG + PIA);
      only views and `.live` wiring are per-app.
- [ ] Reducer tests construct the reducer with test dependencies and assert output state — no device,
      minimal setup.

## Choosing MVI or MVVM

MVI is **not** universal. Reach for it when state is a genuine state machine
(connecting / connected / reconnecting / error), when there are optimistic updates or error recovery,
when correctness must be unit-test-provable (VPN, auth, purchases), or when multiple async inputs
converge. MVVM remains acceptable for simple, read-only, low-risk screens and for subviews.

In existing code, follow the local pattern. Do not rewrite a working screen unless the surrounding
work justifies it.

## Notes and known limits

- **iOS 15 target.** `Store` uses `ObservableObject` + `@Published` because `@Observable` needs
  iOS 17. When the target moves, the swap is localized to `Store` — views already read `store.state`
  without knowing the mechanism.
- **No `scope` / `pullback`.** Composition is deliberately by plain arguments: a sub-view takes a
  state slice and a `send` closure. ADR 0010 settled this; do not add TCA-style scoping.
- **No Use Case layer.** The reducer plays that role. Logic shared across features graduates to a
  `Service`, not a Use Case class.
- **Swift 5 language mode.** `Effect` carries no `Sendable` constraints yet, so strict-concurrency
  adoption is still open work.
- **Stepping stone to TCA.** Every concept here maps directly onto TCA. If the hand-rolled design is
  outgrown, migration is evolution rather than rewrite.

## References

- [`ADRs/0010-unidirectional-mvi-architecture.md`](../../ADRs/0010-unidirectional-mvi-architecture.md)
  — state and business logic
- [`ADRs/0009-ios-coordinator-navigation-pattern.md`](../../ADRs/0009-ios-coordinator-navigation-pattern.md)
  — navigation
