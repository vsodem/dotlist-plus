import Foundation

/// Behavior source of truth: docs/APP_RULES.md, sections 3–6.
/// No UI or persistence code belongs in this file.
public enum ListRules {
    public static func transition(_ state: ListState, _ change: ListChange, now: Double = Date().timeIntervalSince1970 * 1000) throws -> ListState {
        try WorkItemRules.validate(state)
        try validateSelection(state)
        var next = state
        switch change {
        case .beginReview:
            try WorkItemRules.requireIdle(next)
            let available = next.actionOrder.filter { next.workItem($0).map { WorkItemRules.available($0, in: next) } ?? false }
            if let first = available.first {
                next.selection.phase = .reviewing
                next.selection.candidateActionIDs = available
                next.selection.dottedActionIDs = [first]
                next.selection.candidateIndex = 1
                finishReviewIfNeeded(&next)
            }
        case .answerReview(let yes):
            guard let candidate = next.candidate else { throw RuleError("There is no review question to answer.") }
            if yes { next.selection.dottedActionIDs.append(candidate.id) }
            next.selection.candidateIndex += 1
            finishReviewIfNeeded(&next)
        case .completeNextAction, .recordPartialWork:
            guard next.selection.phase == .executing, let id = next.selection.dottedActionIDs.last,
                  let index = next.workItems.firstIndex(where: { $0.id == id }) else {
                throw RuleError("Only the next dotted action can be worked or completed.")
            }
            next.selection.dottedActionIDs.removeLast()
            next.actionOrder.removeAll { $0 == id }
            if case .completeNextAction = change { next.workItems[index].completedAt = now }
            else { next.actionOrder.append(id) }
            if next.selection.dottedActionIDs.isEmpty { next.selection = SelectionState() }
        case .makeUrgent(let id):
            guard let action = next.workItem(id), WorkItemRules.available(action, in: next) else {
                throw RuleError("This action is blocked. Choose an available prerequisite to make urgent instead.")
            }
            next.actionOrder.removeAll { $0 == id }
            next.actionOrder.append(id)
            next.selection.dottedActionIDs.removeAll { $0 == id }
            next.selection.dottedActionIDs.append(id)
            next.selection.phase = .executing
            next.selection.candidateActionIDs = []
            next.selection.candidateIndex = 0
        case .clearSelection:
            next.selection = SelectionState()
        case .eraseCurrentList:
            next = ListState()
        default:
            try WorkItemRules.apply(change, to: &next)
        }
        try WorkItemRules.validate(next)
        try validateSelection(next)
        return next
    }

    private static func finishReviewIfNeeded(_ state: inout ListState) {
        if state.selection.candidateIndex >= state.selection.candidateActionIDs.count {
            state.selection.phase = .executing
            state.selection.candidateActionIDs = []
            state.selection.candidateIndex = 0
        }
    }

    public static func validateSelection(_ state: ListState) throws {
        let selection = state.selection
        func require(_ condition: Bool) throws {
            if !condition { throw RuleError("The saved selection is invalid. Start a new review; your work items are preserved.") }
        }
        try require(Set(selection.dottedActionIDs).count == selection.dottedActionIDs.count)
        try require(Set(selection.candidateActionIDs).count == selection.candidateActionIDs.count)
        for id in selection.dottedActionIDs + selection.candidateActionIDs {
            try require(state.workItem(id).map { WorkItemRules.available($0, in: state) } ?? false)
        }
        switch selection.phase {
        case .idle:
            try require(selection.dottedActionIDs.isEmpty && selection.candidateActionIDs.isEmpty && selection.candidateIndex == 0)
        case .executing:
            try require(!selection.dottedActionIDs.isEmpty && selection.candidateActionIDs.isEmpty && selection.candidateIndex == 0)
        case .reviewing:
            try require(!selection.dottedActionIDs.isEmpty && selection.candidateIndex > 0 && selection.candidateIndex < selection.candidateActionIDs.count)
            try require(selection.dottedActionIDs.first == selection.candidateActionIDs.first)
            let prefix = Array(selection.candidateActionIDs.prefix(selection.candidateIndex))
            try require(prefix.filter { selection.dottedActionIDs.contains($0) } == selection.dottedActionIDs)
        }
    }
}
