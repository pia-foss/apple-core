# CoreArchitecture

A small, hand-rolled unidirectional store for SwiftUI features, plus the navigation contract that
pairs with it. No dependencies beyond `Foundation` and `Combine`.

*State flows down, actions flow up.*

```
State ──renders──▶ View ──emits──▶ Action
  ▲                                   │
  │ new State                         │ store.send(action)
  └────── reduce(&state, action) ◀────┘
                │
                └─ Effect ──async (injected dependencies)──▶ Action′
```

## Requirements

iOS 15+, macOS 12+, tvOS 15+, watchOS 8+, visionOS 1+. Swift 5.9.

## Installation

```swift
.package(url: "https://github.com/pia-foss/apple-core", .upToNextMinor(from: "0.1.0"))
```

Then add `CoreArchitecture` to your target's dependencies.

## Three invariants

Every guarantee this library offers rests on these. They are not style preferences.

1. **`state` is read-only to views.** The only mutation path is `store.send(_:)`.
2. **`reduce` is pure.** No I/O, no globals, deterministic given its inputs.
3. **All impurity lives behind injected dependencies** and runs only inside effects.

## What ships here

| Type | Role |
|---|---|
| `Store<State, Action>` | `@MainActor ObservableObject`. Holds state, runs `send`, executes effects, feeds their actions back. Supplies `binding(_:send:)` for SwiftUI controls. |
| `Effect<Action>` | A description of async work a reducer returns. Cancellable by id. |
| `TestStore<State, Action>` | Deterministic test driver. Same effect machinery, but effect output is queued for the test. `DEBUG`-only. |
| `Coordinator` | The navigation contract: `func start()`. |

`State`, `Action`, `Reducer` and `Dependencies` are **not** here. They are per-feature types that live
with the feature. This library only provides what they plug into.

## The demo

[`Sources/SpaceshipDemo`](Sources/SpaceshipDemo) is a complete, compiling feature: pick a ship from the
fleet, then launch it. It was chosen because its moments need genuinely different effect shapes —
pre-flight checks (`task`), telemetry (`fireAndForget`), a countdown and an ascent (`stream`, under
separate ids), launch (`merge`), and abort (`cancel`).

Two screens and three stores, one per feature: the fleet list, one launch attempt, and the coordination
between them. The navigation path lives in that third store's state, so a push, a back-swipe and a
cross-feature result are all ordinary reducer transitions, asserted without a view.

To see it: open `Package.swift` in Xcode, **select the `SpaceshipDemo` scheme**, open
`SpaceshipFlow.swift`, show the canvas (`⌥⌘↩`). The scheme matters — previews only run for a file the
active scheme compiles. Or run `swift test --filter SpaceshipDemoTests` for the logic alone.

**[The demo's own README](Sources/SpaceshipDemo/README.md)** is the guided tour: which file to read
first, why each store sits where it does, where each effect factory appears, how the tests are
structured, and what the demo deliberately leaves out. This file explains the pattern; that one explains
where to see it.

The demo builds and is tested with the package, so it cannot drift from the library. It is a product, so
previews and the demo scheme work — meaning a consumer of this package can see it. Depend on the
`CoreArchitecture` product alone and nothing of the demo reaches your app.

## Writing a feature

Group a feature's types under a caseless `enum` namespace. Its own files can then say `State` and
`Action` without repeating the prefix, and `Feature.` lists everything in autocomplete:

```swift
public enum Items {}

extension Items {
    public struct State: Equatable {
        public var items: [Item] = []
        public var isLoading = false
    }

    public enum Action: Equatable {
        case onAppear
        case refreshTapped
        case itemsLoaded([Item])
    }
}
```

`Dependencies` is a struct of the collaborators that keep the reducer pure. Protocols for
collaborators shared across features, typed closures for one-offs. Name each one for what it *is* —
`state.items` is an array and `deps.itemRepository` is a repository, and a shared name would read like the
wrong one at every call site:

```swift
extension Items {
    public struct Dependencies {
        public var itemRepository: any ItemRepository
        public var track: (AnalyticsEvent) -> Void
    }
}
```

`Reducer` is a struct that captures its dependencies at init and mutates state in exactly one place:

```swift
extension Items {
    public struct Reducer {
        public let deps: Dependencies

        public func reduce(_ state: inout State, _ action: Action) -> Effect<Action>? {
            switch action {
            case .onAppear:
                state.isLoading = true
                return .task { [deps] in .itemsLoaded((try? await deps.itemRepository.all()) ?? []) }

            case .refreshTapped:
                // Analytics is I/O, so it goes out as an effect rather than being called inline.
                return .merge(
                    .fireAndForget { [deps] in deps.track(.refreshTapped) },
                    .task { [deps] in .itemsLoaded((try? await deps.itemRepository.all()) ?? []) }
                )

            case .itemsLoaded(let items):
                state.isLoading = false
                state.items = items
                return nil
            }
        }
    }
}
```

The view stays outside the namespace, because it is the per-app layer while the namespace is the
shareable part. It owns the store, reads state, and sends actions. Sub-views take a state slice plus a
`send` closure as plain arguments, so they never know a `Store` exists:

```swift
struct ItemsView: View {
    @StateObject var store: Store<Items.State, Items.Action>

    var body: some View {
        List(store.state.items) { item in
            ItemRow(item: item, send: store.send)
        }
        .task { store.send(.onAppear) }
    }
}
```

Wire dependencies twice: a live value for the app, fakes for tests. The reducer never knows which it
got.

```swift
extension Items.Dependencies {
    static var live: Self {
        .init(itemRepository: DefaultItemRepository(), track: { AnalyticsClient.shared.track($0) })
    }
}
```

## Bindings for text fields, toggles and sliders

`state` is `private(set)`, so `$store.state.email` will not compile — and that is the point. A binding
straight into state would write without passing the reducer, which breaks the first invariant.

Use `binding(_:send:)`. The getter reads state; the setter sends an action:

```swift
TextField("Email", text: store.binding(\.email) { .emailChanged($0) })
Toggle("Remember me", isOn: store.binding(\.remembersMe) { .rememberMeToggled($0) })
Slider(value: store.binding(\.thrust) { .thrustChanged($0) }, in: 0...100)
```

The edit still travels through the reducer, so it is still a plain unit test:

```swift
var state = Login.State()
_ = Login.Reducer(deps: .test).reduce(&state, .emailChanged("pilot@example.com"))
#expect(state.email == "pilot@example.com")
```

Two things to know:

- **One action per edit.** A `TextField` sends one on every keystroke and a `Slider` one per drag
  increment. That is intended — each is a named, auditable mutation — but expensive work the reducer
  triggers belongs in an effect with an `id`, so a later edit debounces the earlier one.
- **One action case per field, deliberately.** There is no generated-binding machinery here (TCA's
  `BindableAction` / `@BindingState`). The cost is a case per editable field; the return is that every
  mutation has a name you can search for, assert on, and see in a reducer's `switch`.

## Effects

| Factory | Use for | Emits |
|---|---|---|
| `.task(id:_:)` | A fetch, a submit, a purchase | one action, or none |
| `.fireAndForget(id:_:)` | Analytics, logging, a persist | nothing |
| `.stream(id:_:)` | Engine observation, timers, retry loops | many actions over time |
| `.merge(_:)` | Several of the above at once | whatever they emit |
| `.cancel(id:)` | Tearing down in-flight work | nothing |

Returning `nil` from `reduce` means "no effect".

### Isolation

Effect bodies are `@MainActor`. This is deliberate. A dependency closure usually wraps something that
is not thread-safe — an existing singleton, a legacy manager, a UI-bound API — and a non-isolated body
would call it from the global executor. Awaiting `deps.fetch()` still releases the main thread, since
the underlying network or engine work runs wherever its own implementation runs, so what stays on the
main actor is only the glue. An effect that genuinely needs to burn CPU should hop off explicitly
rather than assume it may.

### Cancellation

An effect given an `id` is tracked and can be torn down with `.cancel(id:)`. The rule to remember:

> **The same `id` means one at a time.** Starting a new effect under an `id` cancels whatever was
> already in flight under it.

That is the semantic debouncing, retry timers and re-subscription all want. Effects that must
genuinely run concurrently need distinct ids, or none at all.

Cancellation is cooperative, as everywhere in Swift concurrency: the runtime cancels the `Task`, and
the body notices by awaiting something that throws, checking `Task.isCancelled`, or iterating an
`AsyncSequence` that ends on cancellation. Anything still in flight is cancelled when the `Store` is
released, so a `.stream` does not outlive its screen.

```swift
private enum EffectID { case statusUpdates }

case .onAppear:
    return .stream(id: EffectID.statusUpdates) { [deps] send in
        for await status in deps.statusUpdates() {
            send(.statusChanged(status))
        }
    }

case .stopTapped:
    return .merge(
        .cancel(id: EffectID.statusUpdates),
        .task { [deps] in await deps.stop(); return .stopped }
    )
```

`.stream` requires an `id` rather than defaulting it: a stream nobody can cancel runs until the whole
store is torn down, which for a retry loop is a leak rather than a shortcut.

## Testing

A reducer is a pure function, so the cheapest test calls it directly — no runtime, no device. Use this
when the claim is about the synchronous mutation, or about *whether* an effect was returned:

```swift
var state = Items.State()
let effect = Items.Reducer(deps: .test).reduce(&state, .onAppear)

#expect(state.isLoading)
#expect(effect != nil)
```

Use `TestStore` when the claim is about the async round-trip. It runs the same reducer and the same
effect machinery as `Store`, so cancellation and merging behave identically, with one deliberate
difference: **actions produced by effects are queued rather than applied**, and the test decides when
to let them in. That is what makes the round-trip assertable instead of raced.

```swift
@MainActor
@Test
func refresh() async {
    let spy = Spy()
    let store = TestStore(
        initial: Items.State(),
        reduce: Items.Reducer(deps: .init(items: FakeRepository(), track: spy.track)).reduce
    )

    store.send(.refreshTapped)

    let received = await store.receive()          // the effect's action, then applied
    #expect(received == .itemsLoaded([.fixture]))
    #expect(store.state.isLoading == false)

    await store.finish()                          // drain fire-and-forget work
    #expect(spy.events == [.refreshTapped])
    #expect(store.unconsumedActionCount == 0)
}
```

- `receive(timeout:)` returns `nil` on timeout. Assert non-`nil` for a readable failure. It takes no
  XCTest dependency, so it works from Swift Testing (used above) or XCTest alike.
- `finish(timeout:)` waits for in-flight effects, then cancels what is left, since a `.stream` never
  ends on its own. Use it before asserting on a spy that a fire-and-forget effect writes to.
- `unconsumedActionCount` catches an effect that fired more times than expected.

Hand-roll fakes. There is no mocking framework here and none is needed: dependencies are protocols or
closures.

## Navigation

`Coordinator` is the whole contract: `func start()`. A screen never knows what comes next. Views and
view controllers hold no coordinator reference — they expose output closures the coordinator injects,
and the coordinator decides the transition. UIKit and SwiftUI use the identical pattern; the
`UIHostingController` wrap is a coordinator detail.

The `Store` owns state; the coordinator owns transitions. A coordinator starts a feature by creating
its `Store` and handing it to the feature view.

```swift
@MainActor
final class ItemsCoordinator: Coordinator {
    enum Output { case didSelect(Item) }

    private let subject = PassthroughSubject<Output, Never>()
    var output: AnyPublisher<Output, Never> { subject.eraseToAnyPublisher() }

    func start() {
        let store = Store(initial: Items.State(), reduce: Items.Reducer(deps: .live).reduce)
        let view = ItemsView(store: store) { [weak self] item in
            self?.subject.send(.didSelect(item))
        }
        navigationController.pushViewController(UIHostingController(rootView: view), animated: true)
    }
}
```

`start()` is the only requirement. Child-flow storage and subscription bags belong to the concrete
coordinators that need them: not every coordinator has children, not every one uses Combine, and a
protocol cannot supply stored properties anyway.

Discipline the compiler will not enforce, so review must:

- Capture `self` as `weak` in every injected closure, or the coordinator and the closure it handed out
  retain each other.
- Store every subscription. One that is not stored is cancelled immediately and silently.
- Cancel the outgoing subscriptions before replacing a child coordinator.
- Pass data to the next flow through the child coordinator's `init`, not through shared state.

## Review checklist

Nothing in the build system enforces these.

**State and logic**
- [ ] `State` is a value type and `Equatable`; views only read it.
- [ ] Every mutation goes through `store.send(_:)`.
- [ ] `reduce` is pure: no I/O, no globals. If a global appears in a reducer, it belongs in
      `Dependencies`.
- [ ] Analytics, logging and persistence go out as `.fireAndForget`, not inline calls in `reduce`.
- [ ] `Dependencies` has both a live and a test wiring; only the live one knows about globals.

**Effects**
- [ ] Every long-lived effect has an `id` and something cancels it.
- [ ] Two effects sharing an `id` are meant to replace each other, not run concurrently.
- [ ] Effect bodies observe cancellation.

**Navigation**
- [ ] The screen exposes output closures; it holds no coordinator reference and decides nothing.
- [ ] Every injected closure captures `self` as `weak`.
- [ ] Subscriptions are stored, and cancelled before a child coordinator is replaced.

## Choosing this pattern

It is not universal. Reach for it when state is a genuine state machine, when there are optimistic
updates or error recovery, when correctness must be unit-test-provable, or when several async inputs
converge on one screen. A plain view model remains the better choice for simple, read-only screens and
for subviews.

## Known limits

- **Swift 5 language mode.** `Effect` carries no `Sendable` constraints yet, so strict-concurrency
  adoption is open work.
- **`ObservableObject`, not `@Observable`.** Required by the iOS 15 floor. The swap is local to
  `Store`, since views read `store.state` without knowing the mechanism.
- **No `scope` or `pullback`.** Composition is by plain arguments: a sub-view takes a state slice and a
  `send` closure. Deliberate, not missing.
- **SwiftUI is imported in one file only.** `Store+Binding.swift` is behind `#if canImport(SwiftUI)`, so
  the rest of the library stays UI-agnostic and the coupling is visible rather than ambient.
- **No use-case layer.** The reducer plays that role. Logic shared across features becomes a service.
