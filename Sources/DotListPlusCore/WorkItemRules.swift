import Foundation

public enum WorkProgress: Equatable {
    case empty, needsBreakdown, inProgress(completed: Int, total: Int), complete
}

public enum WorkItemRules {
    public static func available(_ workItem: WorkItem, in state: ListState) -> Bool {
        workItem.kind == .action && workItem.completedAt == nil && workItem.prerequisiteIDs.allSatisfy {
            state.workItem($0)?.completedAt != nil
        }
    }

    public static func label(_ workItem: WorkItem, in state: ListState) -> String {
        [state.projects.first { $0.id == workItem.projectID }?.title,
         workItem.outcomeID.flatMap { state.workItem($0)?.title }, workItem.title]
            .compactMap { $0 }.joined(separator: " › ")
    }

    public static func blockers(_ workItem: WorkItem, in state: ListState) -> [WorkItem] {
        workItem.prerequisiteIDs.compactMap(state.workItem).filter { $0.completedAt == nil }
    }

    /// Walk prerequisite branches; the user chooses which available action to expedite.
    public static func availablePrerequisites(of id: ID, in state: ListState) -> [WorkItem] {
        var visited = Set<ID>()
        var availableIDs = Set<ID>()
        func visit(_ current: ID) {
            guard visited.insert(current).inserted, let workItem = state.workItem(current) else { return }
            for prerequisite in workItem.prerequisiteIDs.compactMap(state.workItem) where prerequisite.completedAt == nil {
                if available(prerequisite, in: state) { availableIDs.insert(prerequisite.id) }
                else { visit(prerequisite.id) }
            }
        }
        visit(id)
        return state.actionOrder.filter { availableIDs.contains($0) }.compactMap(state.workItem)
    }

    public static func outcomeProgress(_ id: ID, in state: ListState) -> WorkProgress {
        let children = state.workItems.filter { $0.outcomeID == id }
        guard !children.isEmpty else { return .needsBreakdown }
        let completed = children.filter { $0.completedAt != nil }.count
        return completed == children.count ? .complete : .inProgress(completed: completed, total: children.count)
    }

    public static func projectProgress(_ id: ID, in state: ListState) -> WorkProgress {
        let workItems = state.workItems.filter { $0.projectID == id }
        guard !workItems.isEmpty else { return .empty }
        let actions = workItems.filter { $0.kind == .action }
        let needsBreakdown = workItems.contains { $0.kind == .outcome && outcomeProgress($0.id, in: state) == .needsBreakdown }
        let completed = actions.filter { $0.completedAt != nil }.count
        if needsBreakdown { return .needsBreakdown }
        return completed == actions.count ? .complete : .inProgress(completed: completed, total: actions.count)
    }

    public static func validate(_ state: ListState) throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw RuleError(message) }
        }
        try require(Set(state.projects.map(\.id)).count == state.projects.count, "Project IDs must be unique.")
        try require(Set(state.workItems.map(\.id)).count == state.workItems.count, "Work item IDs must be unique.")
        for project in state.projects {
            try require(!project.id.isEmpty && !project.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "Every project needs an ID and a title.")
        }
        for workItem in state.workItems {
            try require(!workItem.id.isEmpty && !workItem.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "Every work item needs an ID and a title.")
            if let projectID = workItem.projectID {
                try require(state.projects.contains { $0.id == projectID }, "The project for ‘\(workItem.title)’ is missing.")
            }
            if workItem.kind == .outcome {
                try require(workItem.outcomeID == nil && workItem.prerequisiteIDs.isEmpty && workItem.completedAt == nil,
                            "Outcomes cannot have parents, prerequisites, or a stored completion date.")
            }
            if let parentID = workItem.outcomeID {
                guard let parent = state.workItem(parentID), parent.kind == .outcome else {
                    throw RuleError("‘\(workItem.title)’ needs a valid outcome as its parent.")
                }
                try require(parent.projectID == workItem.projectID, "A child must be in the same project as its outcome.")
            }
            try require(Set(workItem.prerequisiteIDs).count == workItem.prerequisiteIDs.count, "A prerequisite cannot be listed twice.")
            if let timestamp = workItem.completedAt {
                try require(timestamp.isFinite && timestamp >= 0, "‘\(workItem.title)’ has an invalid completion date.")
            }
            for id in workItem.prerequisiteIDs {
                guard let prerequisite = state.workItem(id), prerequisite.kind == .action else {
                    throw RuleError("‘\(workItem.title)’ has a missing prerequisite or a prerequisite that is not an action.")
                }
                try require(id != workItem.id, "An action cannot require itself.")
                try require(prerequisite.projectID == workItem.projectID, "Prerequisites must belong to the same project.")
                try require(workItem.completedAt == nil || prerequisite.completedAt != nil,
                            "Reopen ‘\(workItem.title)’ before reopening its prerequisite ‘\(prerequisite.title)’.")
            }
        }
        var visiting = Set<ID>()
        var visited = Set<ID>()
        func visit(_ id: ID) throws {
            if visiting.contains(id) { throw RuleError("These prerequisites would form a circle. No changes were saved.") }
            if visited.contains(id) { return }
            visiting.insert(id)
            for next in state.workItem(id)?.prerequisiteIDs ?? [] { try visit(next) }
            visiting.remove(id)
            visited.insert(id)
        }
        for workItem in state.workItems { try visit(workItem.id) }
        let unfinished = state.workItems.filter { $0.kind == .action && $0.completedAt == nil }.map(\.id)
        try require(Set(state.actionOrder).count == state.actionOrder.count && Set(state.actionOrder) == Set(unfinished),
                    "The action order must contain every unfinished action exactly once.")
    }

    static func requireIdle(_ state: ListState) throws {
        guard state.selection.phase == .idle else {
            throw RuleError("Use Choose again before changing relationships, deleting work, or reopening an action.")
        }
    }

    static func apply(_ change: ListChange, to state: inout ListState) throws {
        switch change {
        case .addProject(let project):
            try requireIdle(state)
            state.projects.append(Project(id: project.id, title: project.title.trimmingCharacters(in: .whitespacesAndNewlines)))
        case .renameProject(let id, let title):
            guard let index = state.projects.firstIndex(where: { $0.id == id }) else { throw RuleError("Project not found.") }
            state.projects[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        case .deleteProject(let id):
            try requireIdle(state)
            guard !state.workItems.contains(where: { $0.projectID == id }) else { throw RuleError("Move or remove this project's work before deleting it.") }
            state.projects.removeAll { $0.id == id }
        case .addWorkItem(var workItem):
            if workItem.kind == .outcome || !workItem.prerequisiteIDs.isEmpty { try requireIdle(state) }
            guard workItem.completedAt == nil else { throw RuleError("New actions must start unfinished.") }
            workItem.title = workItem.title.trimmingCharacters(in: .whitespacesAndNewlines)
            state.workItems.append(workItem)
            if workItem.kind == .action { state.actionOrder.append(workItem.id) }
        case .renameWorkItem(let id, let title):
            guard let index = state.workItems.firstIndex(where: { $0.id == id }) else { throw RuleError("Work item not found.") }
            state.workItems[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        case .updateRelationships(let id, let project, let parent, let prerequisites):
            try requireIdle(state)
            guard let index = state.workItems.firstIndex(where: { $0.id == id }) else { throw RuleError("Work item not found.") }
            state.workItems[index].projectID = project
            state.workItems[index].outcomeID = parent
            state.workItems[index].prerequisiteIDs = prerequisites
            if state.workItems[index].kind == .outcome {
                for child in state.workItems.indices where state.workItems[child].outcomeID == id {
                    state.workItems[child].projectID = project
                }
            }
        case .deleteWorkItem(let id):
            try requireIdle(state)
            guard !state.workItems.contains(where: { $0.prerequisiteIDs.contains(id) }) else {
                throw RuleError("Another action requires this one. Remove that prerequisite link before deleting it.")
            }
            guard !state.workItems.contains(where: { $0.outcomeID == id }) else {
                throw RuleError("Move or remove this outcome's required actions before deleting it.")
            }
            state.workItems.removeAll { $0.id == id }
            state.actionOrder.removeAll { $0 == id }
        case .reopenAction(let id):
            try requireIdle(state)
            guard let index = state.workItems.firstIndex(where: { $0.id == id && $0.kind == .action && $0.completedAt != nil }) else {
                throw RuleError("Only a completed action can be reopened.")
            }
            state.workItems[index].completedAt = nil
            state.actionOrder.append(id)
        case .convertActionToOutcome(let id, let titles):
            try requireIdle(state)
            guard let index = state.workItems.firstIndex(where: { $0.id == id }),
                  let position = state.actionOrder.firstIndex(of: id), state.workItems[index].outcomeID == nil else {
                throw RuleError("Only an unfinished action without a parent can be broken into required actions.")
            }
            guard !titles.isEmpty else { throw RuleError("Add at least one required action.") }
            let original = state.workItems[index]
            let children = titles.map {
                WorkItem(title: $0.trimmingCharacters(in: .whitespacesAndNewlines), projectID: original.projectID,
                         outcomeID: id, prerequisiteIDs: original.prerequisiteIDs)
            }
            state.workItems[index].kind = .outcome
            state.workItems[index].prerequisiteIDs = []
            for dependent in state.workItems.indices where state.workItems[dependent].prerequisiteIDs.contains(id) {
                let replaced = state.workItems[dependent].prerequisiteIDs.flatMap { $0 == id ? children.map(\.id) : [$0] }
                var seen = Set<ID>()
                state.workItems[dependent].prerequisiteIDs = replaced.filter { seen.insert($0).inserted }
            }
            state.workItems.append(contentsOf: children)
            state.actionOrder.replaceSubrange(position...position, with: children.map(\.id))
        case .beginReview, .answerReview, .completeNextAction, .recordPartialWork,
             .makeUrgent, .clearSelection, .eraseCurrentList:
            throw RuleError("This operation is not a work item change.")
        }
    }
}
