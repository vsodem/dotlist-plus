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

public struct WorkItem: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case action, outcome }
    public let id: ID
    public var title: String
    public var kind: Kind
    public var projectID: ID?
    public var outcomeID: ID?
    public var prerequisiteIDs: [ID]
    public var completedAt: Double?

    public init(id: ID = UUID().uuidString, title: String, kind: Kind = .action,
                projectID: ID? = nil, outcomeID: ID? = nil, prerequisiteIDs: [ID] = [],
                completedAt: Double? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.projectID = projectID
        self.outcomeID = outcomeID
        self.prerequisiteIDs = prerequisiteIDs
        self.completedAt = completedAt
    }
}

public struct SelectionState: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case idle, reviewing, executing }
    public var phase: Phase = .idle
    public var dottedActionIDs: [ID] = []
    public var candidateActionIDs: [ID] = []
    public var candidateIndex: Int = 0
    public init() {}
}

public struct ListState: Codable, Equatable, Sendable {
    public var projects: [Project] = []
    public var workItems: [WorkItem] = []
    public var actionOrder: [ID] = []
    public var selection = SelectionState()
    public init() {}

    public func workItem(_ id: ID) -> WorkItem? { workItems.first { $0.id == id } }
    public var nextAction: WorkItem? {
        guard selection.phase == .executing else { return nil }
        return selection.dottedActionIDs.last.flatMap(workItem)
    }
    public var reviewBenchmark: WorkItem? {
        guard selection.phase == .reviewing else { return nil }
        return selection.dottedActionIDs.last.flatMap(workItem)
    }
    public var candidate: WorkItem? {
        guard selection.phase == .reviewing, selection.candidateActionIDs.indices.contains(selection.candidateIndex) else { return nil }
        return workItem(selection.candidateActionIDs[selection.candidateIndex])
    }
}

public struct RuleError: Error, LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Every UI operation passes through one atomic, validated transition.
public enum ListChange: Sendable {
    case addProject(Project)
    case renameProject(ID, String)
    case deleteProject(ID)
    case addWorkItem(WorkItem)
    case renameWorkItem(ID, String)
    case updateRelationships(ID, project: ID?, parent: ID?, prerequisites: [ID])
    case deleteWorkItem(ID)
    case reopenAction(ID)
    case convertActionToOutcome(ID, titles: [String])
    case beginReview
    case answerReview(Bool)
    case completeNextAction
    case recordPartialWork
    case makeUrgent(ID)
    case clearSelection
    case eraseCurrentList
}
