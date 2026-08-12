#if canImport(SwiftUI)

    import SwiftUI

    extension Store {

        /// A two-way binding for a SwiftUI control, reading from state and writing by sending an action.
        ///
        /// `TextField`, `Toggle`, `Slider`, `Stepper` and `Picker` all require a `Binding`, which `state`
        /// cannot supply on its own — it is `private(set)` precisely so nothing writes to it directly.
        /// This preserves that: the getter reads state, the setter sends an action, so an edit still
        /// travels through the reducer and is still assertable in a test.
        ///
        /// ```swift
        /// TextField("Email", text: store.binding(\.email) { .emailChanged($0) })
        /// Toggle("Remember me", isOn: store.binding(\.remembersMe) { .rememberMeToggled($0) })
        /// ```
        ///
        /// - Important: One action per edit. A control that emits continuously — a `Slider` being
        ///   dragged, or a `TextField` on every keystroke — sends one action each time, so any expensive
        ///   work the reducer triggers belongs in an effect with an `id` that debounces it.
        ///
        /// - Parameters:
        ///   - keyPath: Reads the value out of state.
        ///   - action: Wraps an edited value in the action that applies it.
        /// - Returns: A binding whose writes are dispatched rather than applied.
        public func binding<Value>(
            _ keyPath: KeyPath<State, Value>,
            send action: @escaping (Value) -> Action
        ) -> Binding<Value> {
            Binding(
                // Captured strongly on purpose: a getter has no value to fall back on if the store is
                // gone, and the binding never outlives the view that owns the store anyway.
                get: { self.state[keyPath: keyPath] },
                set: { [weak self] value in self?.send(action(value)) }
            )
        }
    }

#endif
