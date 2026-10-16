import Foundation

public typealias ID = String

public struct Project: Identifiable, Codable, Equatable, Sendable {
    public let id: ID
    public var title: String
    public init(id: ID = UUID().uuidString, title: String) {
        self.id = id
        self.title = title
    }
}

public struct WorkTask: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case action, group }
    public let id: ID
    public var title: String
    public var kind: Kind
    public var projectId: ID?
    public var parentId: ID?
    public var prerequisiteIds: [ID]
    public var completedAt: Double?

    public init(id: ID = UUID().uuidString, title: String, kind: Kind = .action,
                projectId: ID? = nil, parentId: ID? = nil, prerequisiteIds: [ID] = [],
                completedAt: Double? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.projectId = projectId
        self.parentId = parentId
        self.prerequisiteIds = prerequisiteIds
        self.completedAt = completedAt
    }
}

public struct Selection: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case idle, reviewing, executing }
    public var phase: Phase = .idle
    public var chain: [ID] = []
    public var candidates: [ID] = []
    public var cursor: Int = 0
    public init() {}
}

public struct AppState: Codable, Equatable, Sendable {
    public var schemaVersion = 2
    public var projects: [Project] = []
    public var tasks: [WorkTask] = []
    public var actionOrder: [ID] = []
    public var selection = Selection()
    public init() {}

    public func task(_ id: ID) -> WorkTask? { tasks.first { $0.id == id } }
    public var nextAction: WorkTask? { selection.chain.last.flatMap(task) }
    public var candidate: WorkTask? {
        guard selection.phase == .reviewing, selection.candidates.indices.contains(selection.cursor) else { return nil }
        return task(selection.candidates[selection.cursor])
    }
}

public struct RuleError: Error, LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Every UI operation passes through one atomic, validated transition.
public enum Change: Sendable {
    case addProject(Project)
    case renameProject(ID, String)
    case deleteProject(ID)
    case addTask(WorkTask)
    case renameTask(ID, String)
    case relationships(ID, project: ID?, parent: ID?, prerequisites: [ID])
    case deleteTask(ID)
    case reopen(ID)
    case breakDown(ID, titles: [String])
    case beginReview
    case answer(Bool)
    case complete
    case partial
    case urgent(ID)
    case chooseAgain
    case eraseAll
}
