import Foundation

/// Namespace for the machinery that executes effects.
///
/// A caseless `enum`, so nothing can instantiate it. Effect semantics live here alone, shared by
/// `Store` and `TestStore` so that cancellation behaves identically in an app and under test.
enum EffectRuntime {

    /// Identifies a tracked effect task.
    ///
    /// `explicit` keys come from the `id` a reducer attached and are what cancellation targets.
    /// `anonymous` keys are minted for effects that opted out: no reducer can name them, but the
    /// runtime still needs a handle to await them and to tear them down.
    enum TaskKey: Hashable {
        case explicit(AnyHashable)
        case anonymous(UInt64)
    }

    /// The in-flight effect tasks of one runtime, keyed for cancellation.
    ///
    /// A reference type rather than stored state on `Store` so that `Store.deinit` — which is not
    /// main-actor isolated — can still cancel outstanding work. Every other access happens on the
    /// main actor, and `Task.cancel()` is safe from any thread; together that is what makes the
    /// `@unchecked Sendable` conformance sound rather than merely convenient.
    final class Tasks: @unchecked Sendable {

        /// One entry per key.
        ///
        /// `token` identifies the generation, so a task that finishes late never evicts the newer
        /// task that already replaced it under the same key.
        private var entries: [TaskKey: (token: UInt64, task: Task<Void, Never>)] = [:]
        private var nextToken: UInt64 = 0

        var isEmpty: Bool { entries.isEmpty }

        /// Reserves the next generation token, which also gives `anonymous` keys their uniqueness.
        func makeToken() -> UInt64 {
            nextToken += 1
            return nextToken
        }

        /// Tracks `task` under `key`, cancelling whatever was in flight under the same key.
        func register(_ task: Task<Void, Never>, key: TaskKey, token: UInt64) {
            entries[key]?.task.cancel()
            entries[key] = (token, task)
        }

        /// Stops tracking `key`, but only while it still holds the generation named by `token`.
        func finish(key: TaskKey, token: UInt64) {
            guard entries[key]?.token == token else { return }
            entries[key] = nil
        }

        func cancel(id: AnyHashable) {
            let key = TaskKey.explicit(id)
            entries[key]?.task.cancel()
            entries[key] = nil
        }

        func cancelAll() {
            for entry in entries.values {
                entry.task.cancel()
            }
            entries.removeAll()
        }
    }

    /// Executes `effect`, tracking spawned work in `tasks` and routing the actions it produces to
    /// `sink`.
    @MainActor
    static func run<Action>(
        _ effect: Effect<Action>,
        tasks: Tasks,
        sink: @escaping Effect<Action>.Send
    ) {
        switch effect.operation {
        case .merge(let effects):
            for effect in effects {
                run(effect, tasks: tasks, sink: sink)
            }

        case .cancel(let id):
            tasks.cancel(id: id)

        case .run(let id, let work):
            let token = tasks.makeToken()
            let key = id.map(TaskKey.explicit) ?? .anonymous(token)
            // Inherits the main actor from this isolated function, matching `work`'s own isolation,
            // and is enqueued there — so it cannot begin before `register` below runs.
            let task = Task {
                await work(sink)
                tasks.finish(key: key, token: token)
            }
            tasks.register(task, key: key, token: token)
        }
    }
}
