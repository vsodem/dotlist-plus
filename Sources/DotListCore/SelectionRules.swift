import Foundation

/// Behavior source of truth: docs/APP_RULES.md, sections 3–6.
/// No UI or persistence code belongs in this file.
public enum SelectionRules {
    public static func transition(_ state: AppState, _ change: Change, now: Double = Date().timeIntervalSince1970 * 1000) throws -> AppState {
        try TaskRules.validate(state)
        try validate(state)
        var next = state
        switch change {
        case .beginReview:
            try TaskRules.requireIdle(next)
            let available = next.actionOrder.filter { next.task($0).map { TaskRules.available($0, in: next) } ?? false }
            if let first = available.first {
                next.selection.phase = .reviewing
                next.selection.candidates = available
                next.selection.chain = [first]
                next.selection.cursor = 1
                finishReviewIfNeeded(&next)
            }
        case .answer(let yes):
            guard let candidate = next.candidate else { throw RuleError("There is no review question to answer.") }
            if yes { next.selection.chain.append(candidate.id) }
            next.selection.cursor += 1
            finishReviewIfNeeded(&next)
        case .complete, .partial:
            guard next.selection.phase == .executing, let id = next.selection.chain.last,
                  let index = next.tasks.firstIndex(where: { $0.id == id }) else {
                throw RuleError("Only the next dotted action can be worked or completed.")
            }
            next.selection.chain.removeLast()
            next.actionOrder.removeAll { $0 == id }
            if case .complete = change { next.tasks[index].completedAt = now }
            else { next.actionOrder.append(id) }
            if next.selection.chain.isEmpty { next.selection = Selection() }
        case .urgent(let id):
            guard let action = next.task(id), TaskRules.available(action, in: next) else {
                throw RuleError("This action is blocked. Choose an available prerequisite to make urgent instead.")
            }
            next.actionOrder.removeAll { $0 == id }
            next.actionOrder.append(id)
            next.selection.chain.removeAll { $0 == id }
            next.selection.chain.append(id)
            next.selection.phase = .executing
            next.selection.candidates = []
            next.selection.cursor = 0
        case .chooseAgain:
            next.selection = Selection()
        case .eraseAll:
            next = AppState()
        default:
            try TaskRules.apply(change, to: &next)
        }
        try TaskRules.validate(next)
        try validate(next)
        return next
    }

    private static func finishReviewIfNeeded(_ state: inout AppState) {
        if state.selection.cursor >= state.selection.candidates.count {
            state.selection.phase = .executing
            state.selection.candidates = []
            state.selection.cursor = 0
        }
    }

    public static func validate(_ state: AppState) throws {
        let selection = state.selection
        func require(_ condition: Bool) throws {
            if !condition { throw RuleError("The saved selection is invalid. Start a new review; your tasks are preserved.") }
        }
        try require(Set(selection.chain).count == selection.chain.count)
        try require(Set(selection.candidates).count == selection.candidates.count)
        for id in selection.chain + selection.candidates {
            try require(state.task(id).map { TaskRules.available($0, in: state) } ?? false)
        }
        switch selection.phase {
        case .idle:
            try require(selection.chain.isEmpty && selection.candidates.isEmpty && selection.cursor == 0)
        case .executing:
            try require(!selection.chain.isEmpty && selection.candidates.isEmpty && selection.cursor == 0)
        case .reviewing:
            try require(!selection.chain.isEmpty && selection.cursor > 0 && selection.cursor < selection.candidates.count)
            try require(selection.chain.first == selection.candidates.first)
            let prefix = Array(selection.candidates.prefix(selection.cursor))
            try require(prefix.filter { selection.chain.contains($0) } == selection.chain)
        }
    }
}
