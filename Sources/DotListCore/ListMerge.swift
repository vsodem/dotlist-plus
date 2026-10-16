import Foundation

public enum MergeChoice: String, Codable, Sendable { case local, remote }

public struct MergeConflict: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let localDescription: String
    public let remoteDescription: String
}

public struct MergeResult: Sendable {
    public let state: AppState?
    public let conflicts: [MergeConflict]
    public let notice: String?
}

/// Combines snapshots without mutating any input. Unresolved choices never produce a saveable state.
public enum ListMerge {
    public static func merge(base: AppState?, local: AppState, remote: AppState,
                             choices: [String: MergeChoice] = [:]) throws -> MergeResult {
        for state in [base, local, remote].compactMap({ $0 }) {
            try TaskRules.validate(state)
            try SelectionRules.validate(state)
        }
        // A structural fallback must remain resolvable even when field choices are incompatible.
        if let choice = choices["list.structure"] {
            return MergeResult(state: choice == .local ? local : remote, conflicts: [], notice: nil)
        }
        var resolver = Resolver(choices: choices)
        var merged = AppState()
        merged.projects = mergeRecords(base: base?.projects ?? [], local: local.projects, remote: remote.projects,
                                       category: "project", resolver: &resolver) { old, left, right, resolver in
            Project(id: left.id, title: resolver.field(base: old?.title, local: left.title, remote: right.title,
                    id: "project.\(left.id).title", title: "Project title", describe: { $0 }))
        }
        merged.tasks = mergeRecords(base: base?.tasks ?? [], local: local.tasks, remote: remote.tasks,
                                    category: "task", resolver: &resolver) { old, left, right, resolver in
            var task = left
            task.title = resolver.field(base: old?.title, local: left.title, remote: right.title,
                                        id: "task.\(left.id).title", title: "Title for ‘\(left.title)’", describe: { $0 })
            let links = resolver.field(base: old.map(Relationships.init), local: Relationships(left), remote: Relationships(right),
                                       id: "task.\(left.id).relationships", title: "Relationships for ‘\(left.title)’",
                                       describe: { $0.description(in: $0 == Relationships(left) ? local : remote) })
            task.kind = links.kind
            task.projectId = links.project
            task.parentId = links.parent
            task.prerequisiteIds = links.prerequisites
            task.completedAt = resolver.field(base: old.map { $0.completedAt }, local: left.completedAt, remote: right.completedAt,
                                              id: "task.\(left.id).completion", title: "Completion for ‘\(left.title)’",
                                              describe: { $0.map { "Completed at \($0)" } ?? "Unfinished" })
            return task
        }
        let unfinished = merged.tasks.filter { $0.kind == .action && $0.completedAt == nil }.map(\.id)
        merged.actionOrder = mergeOrder(base: base?.actionOrder ?? [], local: local.actionOrder, remote: remote.actionOrder,
                                        ids: unfinished, resolver: &resolver, tasks: merged.tasks)
        guard resolver.conflicts.isEmpty else {
            return MergeResult(state: nil, conflicts: resolver.conflicts, notice: nil)
        }
        do {
            try TaskRules.validate(merged)
        } catch {
            return MergeResult(state: nil, conflicts: [MergeConflict(id: "list.structure",
                title: "These changes cannot be combined: \(error.localizedDescription)",
                localDescription: "Keep this device’s entire list (\(local.tasks.count) tasks).",
                remoteDescription: "Keep the shared entire list (\(remote.tasks.count) tasks).")], notice: nil)
        }

        var notice: String?
        if local.selection == remote.selection {
            merged.selection = local.selection
        } else if let base, local.selection == base.selection {
            merged.selection = remote.selection
        } else if let base, remote.selection == base.selection {
            merged.selection = local.selection
        } else if base == nil && local.selection == Selection() {
            merged.selection = remote.selection
        } else if base == nil && remote.selection == Selection() {
            merged.selection = local.selection
        } else {
            notice = "Review progress changed on both devices. Start a new review; your tasks are preserved."
        }
        do {
            try SelectionRules.validate(merged)
        } catch {
            merged.selection = Selection()
            notice = "The merged tasks changed the saved review. Start a new review; your tasks are preserved."
        }
        try TaskRules.validate(merged)
        try SelectionRules.validate(merged)
        return MergeResult(state: merged, conflicts: [], notice: notice)
    }

    private struct Relationships: Equatable {
        let kind: WorkTask.Kind
        let project: ID?
        let parent: ID?
        let prerequisites: [ID]

        init(_ task: WorkTask) {
            kind = task.kind
            project = task.projectId
            parent = task.parentId
            prerequisites = task.prerequisiteIds
        }

        func description(in state: AppState) -> String {
            let projectTitle = project.flatMap { id in state.projects.first { $0.id == id }?.title } ?? "None"
            let parentTitle = parent.flatMap { state.task($0)?.title } ?? "None"
            let required = prerequisites.map { state.task($0)?.title ?? $0 }.joined(separator: ", ")
            return "\(kind == .group ? "Broad task" : "Action"); project: \(projectTitle); parent: \(parentTitle); prerequisites: \(required.isEmpty ? "None" : required)"
        }
    }

    private struct Resolver {
        let choices: [String: MergeChoice]
        var conflicts: [MergeConflict] = []

        mutating func field<T: Equatable>(base: T?, local: T, remote: T, id: String, title: String,
                                          describe: (T) -> String) -> T {
            if local == remote { return local }
            if let base {
                if local == base { return remote }
                if remote == base { return local }
            }
            if let choice = choices[id] { return choice == .local ? local : remote }
            conflicts.append(MergeConflict(id: id, title: title,
                                           localDescription: describe(local), remoteDescription: describe(remote)))
            return local
        }
    }

    private static func mergeRecords<T: Identifiable & Equatable>(base: [T], local: [T], remote: [T],
            category: String, resolver: inout Resolver,
            combine: (T?, T, T, inout Resolver) -> T) -> [T] where T.ID == ID {
        let before = Dictionary(uniqueKeysWithValues: base.map { ($0.id, $0) })
        let left = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let right = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        // Record array order is not action order. Keep the shared order so devices converge
        // instead of repeatedly uploading their own arrangement of the same records.
        return unique(remote.map(\.id) + local.map(\.id)).compactMap { id in
            let old = before[id]
            switch (left[id], right[id]) {
            case (.some(let l), .some(let r)):
                return combine(old, l, r, &resolver)
            case (.some(let value), nil), (nil, .some(let value)):
                guard let old else { return value }
                if value == old { return nil }
                return resolver.field(base: .some(old), local: left[id], remote: right[id],
                                      id: "\(category).\(id).deletion", title: "Deleted or edited \(category)", describe: {
                    guard let record = $0 else { return "Delete" }
                    if let task = record as? WorkTask { return "Keep edited task ‘\(task.title)’" }
                    if let project = record as? Project { return "Keep edited project ‘\(project.title)’" }
                    return "Keep edited item"
                })
            case (nil, nil): return nil
            }
        }
    }

    private static func unique(_ ids: [ID]) -> [ID] {
        var seen = Set<ID>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func mergeOrder(base: [ID], local: [ID], remote: [ID], ids: [ID],
                                   resolver: inout Resolver, tasks: [WorkTask]) -> [ID] {
        let allowed = Set(ids)
        let common = Set(local).intersection(remote).intersection(allowed)
        let priority = local.filter { common.contains($0) }
        let positions = [base, local, remote].map { order in
            Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        }
        var edges: [ID: Set<ID>] = [:]
        var conflicting = false
        // Compare shared actions; anchor one-sided additions afterward so stale positions do not undo a reorder.
        for (offset, a) in priority.enumerated() {
            for b in priority.dropFirst(offset + 1) {
                let directions: [Bool?] = positions.map { position in
                    guard let first = position[a], let second = position[b] else { return nil }
                    return first < second
                }
                let old = directions[0], left = directions[1], right = directions[2]
                let direction: Bool?
                if left == right { direction = left }
                else if left == nil { direction = right }
                else if right == nil { direction = left }
                else if left == old { direction = right }
                else if right == old { direction = left }
                else { conflicting = true; direction = left }
                if let direction {
                    edges[direction ? a : b, default: []].insert(direction ? b : a)
                }
            }
        }
        var remaining = Set(priority)
        var ordered: [ID] = []
        while let next = priority.first(where: { id in
            remaining.contains(id) && !remaining.contains { edges[$0]?.contains(id) ?? false }
        }) {
            ordered.append(next)
            remaining.remove(next)
        }
        if !conflicting && remaining.isEmpty {
            insertMissing(from: local.filter { allowed.contains($0) }, into: &ordered)
            insertMissing(from: remote.filter { allowed.contains($0) }, into: &ordered)
            return unique(ordered + ids)
        }
        let conflictID = "list.order"
        if resolver.choices[conflictID] == nil {
            func describe(_ order: [ID]) -> String {
                order.filter { allowed.contains($0) }.map { id in tasks.first { $0.id == id }?.title ?? id }.joined(separator: " → ")
            }
            resolver.conflicts.append(MergeConflict(id: conflictID, title: "Action order changed on both devices",
                localDescription: describe(local), remoteDescription: describe(remote)))
        }
        let preferRemote = resolver.choices[conflictID] == .remote
        var result = (preferRemote ? remote : local).filter { allowed.contains($0) }
        let other = (preferRemote ? local : remote).filter { allowed.contains($0) }
        insertMissing(from: other, into: &result)
        return unique(result + ids)
    }

    // Preserve the chosen sequence, inserting additions after their nearest preceding action.
    private static func insertMissing(from other: [ID], into result: inout [ID]) {
        for (index, id) in other.enumerated() where !result.contains(id) {
            let next = other.dropFirst(index + 1).first(where: { result.contains($0) })
            if next == nil {
                result.append(id)
            } else if let previous = other[..<index].last(where: { result.contains($0) }), let position = result.firstIndex(of: previous) {
                result.insert(id, at: position + 1)
            } else if let next, let position = result.firstIndex(of: next) {
                result.insert(id, at: position)
            } else { result.append(id) }
        }
    }
}
