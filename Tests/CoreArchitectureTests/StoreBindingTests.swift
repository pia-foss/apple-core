#if canImport(SwiftUI)

    import SwiftUI
    import Testing

    @testable import CoreArchitecture

    /// Covers the one thing `binding(_:send:)` has to guarantee: a SwiftUI control can write, and the
    /// write still goes through the reducer.
    ///
    /// If a binding ever mutated state directly, the reducer would stop being the single mutation path
    /// and nothing else in the library would be trustworthy.
    @MainActor
    struct StoreBindingTests {

        private struct FormState: Equatable {
            var email = ""
            var remembersMe = false
        }

        private enum FormAction: Equatable {
            case emailChanged(String)
            case rememberMeToggled(Bool)
        }

        /// Records what the reducer saw, so a test can prove the edit arrived as an action.
        private final class Spy {
            var actions: [FormAction] = []
        }

        private func makeStore(spy: Spy) -> Store<FormState, FormAction> {
            Store(initial: FormState()) { state, action in
                spy.actions.append(action)
                switch action {
                case .emailChanged(let email):
                    state.email = email
                case .rememberMeToggled(let remembers):
                    state.remembersMe = remembers
                }
                return nil
            }
        }

        @Test
        func bindingGetReadsThroughToState() {
            let spy = Spy()
            let store = makeStore(spy: spy)
            store.send(.emailChanged("pilot@example.com"))

            let binding = store.binding(\.email) { .emailChanged($0) }

            #expect(binding.wrappedValue == "pilot@example.com")
        }

        @Test
        func bindingSetSendsAnActionRatherThanMutatingState() {
            let spy = Spy()
            let store = makeStore(spy: spy)
            let binding = store.binding(\.email) { .emailChanged($0) }

            binding.wrappedValue = "atlas@example.com"

            // The write became an action, which is what keeps the reducer the only mutation path.
            #expect(spy.actions == [.emailChanged("atlas@example.com")])
            #expect(store.state.email == "atlas@example.com")
        }

        @Test
        func bindingWorksForANonStringValue() {
            let spy = Spy()
            let store = makeStore(spy: spy)
            let binding = store.binding(\.remembersMe) { .rememberMeToggled($0) }

            binding.wrappedValue = true

            #expect(spy.actions == [.rememberMeToggled(true)])
            #expect(store.state.remembersMe)
        }

        @Test
        func everyEditSendsItsOwnAction() {
            let spy = Spy()
            let store = makeStore(spy: spy)
            let binding = store.binding(\.email) { .emailChanged($0) }

            // A TextField behaves like this — one action per keystroke, which is why expensive reducer
            // work belongs in a debounced effect rather than inline.
            for text in ["a", "at", "atl"] {
                binding.wrappedValue = text
            }

            #expect(
                spy.actions == [.emailChanged("a"), .emailChanged("at"), .emailChanged("atl")]
            )
        }
    }

#endif
