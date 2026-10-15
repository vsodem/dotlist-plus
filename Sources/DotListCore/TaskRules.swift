import Foundation

public enum Progress: Equatable {
    case empty, needsBreakdown, inProgress(completed: Int, total: Int), complete
}

public enum TaskRules {
    public static func available(_ task: WorkTask, in state: AppState) -> Bool {
        task.kind == .action && task.completedAt == nil && task.prerequisiteIds.allSatisfy {
            state.task($0)?.completedAt != nil
        }
    }

    public static func label(_ task: WorkTask, in state: AppState) -> String {
        [state.projects.first { $0.id == task.projectId }?.title,
         task.parentId.flatMap { state.task($0)?.title }, task.title]
            .compactMap { $0 }.joined(separator: " › ")
    }

    public static func blockers(_ task: WorkTask, in state: AppState) -> [WorkTask] {
        task.prerequisiteIds.compactMap(state.task).filter { $0.completedAt == nil }
    }

    /// Walk prerequisite branches; the user chooses which available action to expedite.
    public static func availablePrerequisites(of id: ID, in state: AppState) -> [WorkTask] {
        var visited = Set<ID>()
        var availableIDs = Set<ID>()
        func visit(_ current: ID) {
            guard visited.insert(current).inserted, let task = state.task(current) else { return }
            for prerequisite in task.prerequisiteIds.compactMap(state.task) where prerequisite.completedAt == nil {
                if available(prerequisite, in: state) { availableIDs.insert(prerequisite.id) }
                else { visit(prerequisite.id) }
            }
        }
        visit(id)
        return state.actionOrder.filter { availableIDs.contains($0) }.compactMap(state.task)
    }

    public static func groupProgress(_ id: ID, in state: AppState) -> Progress {
        let children = state.tasks.filter { $0.parentId == id }
        guard !children.isEmpty else { return .needsBreakdown }
        let completed = children.filter { $0.completedAt != nil }.count
        return completed == children.count ? .complete : .inProgress(completed: completed, total: children.count)
    }

    public static func projectProgress(_ id: ID, in state: AppState) -> Progress {
        let tasks = state.tasks.filter { $0.projectId == id }
        guard !tasks.isEmpty else { return .empty }
        let actions = tasks.filter { $0.kind == .action }
        let needsBreakdown = tasks.contains { $0.kind == .group && groupProgress($0.id, in: state) == .needsBreakdown }
        let completed = actions.filter { $0.completedAt != nil }.count
        if needsBreakdown { return .needsBreakdown }
        return completed == actions.count ? .complete : .inProgress(completed: completed, total: actions.count)
    }

    public static func validate(_ state: AppState) throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw RuleError(message) }
        }
        try require(state.schemaVersion == 2, "This file uses an unsupported version of Dot List.")
        try require(Set(state.projects.map(\.id)).count == state.projects.count, "Project IDs must be unique.")
        try require(Set(state.tasks.map(\.id)).count == state.tasks.count, "Task IDs must be unique.")
        for project in state.projects {
            try require(!project.id.isEmpty && !project.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "Every project needs an ID and a title.")
        }
        for task in state.tasks {
            try require(!task.id.isEmpty && !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "Every task needs an ID and a title.")
            if let projectID = task.projectId {
                try require(state.projects.contains { $0.id == projectID }, "The project for ‘\(task.title)’ is missing.")
            }
            if task.kind == .group {
                try require(task.parentId == nil && task.prerequisiteIds.isEmpty && task.completedAt == nil,
                            "Broad tasks cannot have parents, prerequisites, or a stored completion date.")
            }
            if let parentID = task.parentId {
                guard let parent = state.task(parentID), parent.kind == .group else {
                    throw RuleError("‘\(task.title)’ needs a valid broad task as its parent.")
                }
                try require(parent.projectId == task.projectId, "A child must be in the same project as its broad task.")
            }
            try require(Set(task.prerequisiteIds).count == task.prerequisiteIds.count, "A prerequisite cannot be listed twice.")
            if let timestamp = task.completedAt {
                try require(timestamp.isFinite && timestamp >= 0, "‘\(task.title)’ has an invalid completion date.")
            }
            for id in task.prerequisiteIds {
                guard let prerequisite = state.task(id), prerequisite.kind == .action else {
                    throw RuleError("‘\(task.title)’ has a missing prerequisite or a prerequisite that is not an action.")
                }
                try require(id != task.id, "An action cannot require itself.")
                try require(prerequisite.projectId == task.projectId, "Prerequisites must belong to the same project.")
                try require(task.completedAt == nil || prerequisite.completedAt != nil,
                            "Reopen ‘\(task.title)’ before reopening its prerequisite ‘\(prerequisite.title)’.")
            }
        }
        var visiting = Set<ID>()
        var visited = Set<ID>()
        func visit(_ id: ID) throws {
            if visiting.contains(id) { throw RuleError("These prerequisites would form a circle. No changes were saved.") }
            if visited.contains(id) { return }
            visiting.insert(id)
            for next in state.task(id)?.prerequisiteIds ?? [] { try visit(next) }
            visiting.remove(id)
            visited.insert(id)
        }
        for task in state.tasks { try visit(task.id) }
        let unfinished = state.tasks.filter { $0.kind == .action && $0.completedAt == nil }.map(\.id)
        try require(Set(state.actionOrder).count == state.actionOrder.count && Set(state.actionOrder) == Set(unfinished),
                    "The action order must contain every unfinished action exactly once.")
    }

    static func requireIdle(_ state: AppState) throws {
        guard state.selection.phase == .idle else {
            throw RuleError("Use Choose again before changing relationships, deleting work, or reopening an action.")
        }
    }

    static func apply(_ change: Change, to state: inout AppState) throws {
        switch change {
        case .addProject(let project):
            try requireIdle(state)
            state.projects.append(Project(id: project.id, title: project.title.trimmingCharacters(in: .whitespacesAndNewlines)))
        case .renameProject(let id, let title):
            guard let index = state.projects.firstIndex(where: { $0.id == id }) else { throw RuleError("Project not found.") }
            state.projects[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        case .deleteProject(let id):
            try requireIdle(state)
            guard !state.tasks.contains(where: { $0.projectId == id }) else { throw RuleError("Move or remove this project's work before deleting it.") }
            state.projects.removeAll { $0.id == id }
        case .addTask(var task):
            if task.kind == .group || !task.prerequisiteIds.isEmpty { try requireIdle(state) }
            guard task.completedAt == nil else { throw RuleError("New actions must start unfinished.") }
            task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            state.tasks.append(task)
            if task.kind == .action { state.actionOrder.append(task.id) }
        case .renameTask(let id, let title):
            guard let index = state.tasks.firstIndex(where: { $0.id == id }) else { throw RuleError("Task not found.") }
            state.tasks[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        case .relationships(let id, let project, let parent, let prerequisites):
            try requireIdle(state)
            guard let index = state.tasks.firstIndex(where: { $0.id == id }) else { throw RuleError("Task not found.") }
            state.tasks[index].projectId = project
            state.tasks[index].parentId = parent
            state.tasks[index].prerequisiteIds = prerequisites
            if state.tasks[index].kind == .group {
                for child in state.tasks.indices where state.tasks[child].parentId == id {
                    state.tasks[child].projectId = project
                }
            }
        case .deleteTask(let id):
            try requireIdle(state)
            guard !state.tasks.contains(where: { $0.prerequisiteIds.contains(id) }) else {
                throw RuleError("Another action requires this one. Remove that prerequisite link before deleting it.")
            }
            guard !state.tasks.contains(where: { $0.parentId == id }) else {
                throw RuleError("Move or remove this broad task's children before deleting it.")
            }
            state.tasks.removeAll { $0.id == id }
            state.actionOrder.removeAll { $0 == id }
        case .reopen(let id):
            try requireIdle(state)
            guard let index = state.tasks.firstIndex(where: { $0.id == id && $0.kind == .action && $0.completedAt != nil }) else {
                throw RuleError("Only a completed action can be reopened.")
            }
            state.tasks[index].completedAt = nil
            state.actionOrder.append(id)
        case .breakDown(let id, let titles):
            try requireIdle(state)
            guard let index = state.tasks.firstIndex(where: { $0.id == id }),
                  let position = state.actionOrder.firstIndex(of: id), state.tasks[index].parentId == nil else {
                throw RuleError("Only an unfinished action without a parent can be broken into substeps.")
            }
            guard !titles.isEmpty else { throw RuleError("Add at least one substep.") }
            let original = state.tasks[index]
            let children = titles.map {
                WorkTask(title: $0.trimmingCharacters(in: .whitespacesAndNewlines), projectId: original.projectId,
                         parentId: id, prerequisiteIds: original.prerequisiteIds)
            }
            state.tasks[index].kind = .group
            state.tasks[index].prerequisiteIds = []
            for dependent in state.tasks.indices where state.tasks[dependent].prerequisiteIds.contains(id) {
                let replaced = state.tasks[dependent].prerequisiteIds.flatMap { $0 == id ? children.map(\.id) : [$0] }
                var seen = Set<ID>()
                state.tasks[dependent].prerequisiteIds = replaced.filter { seen.insert($0).inserted }
            }
            state.tasks.append(contentsOf: children)
            state.actionOrder.replaceSubrange(position...position, with: children.map(\.id))
        default: throw RuleError("This operation is not a task change.")
        }
    }
}
