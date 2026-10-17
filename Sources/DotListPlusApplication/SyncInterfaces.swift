import DotListPlusCore
import Foundation

public enum RemoteAccount: Equatable, Sendable {
    case available(String)
    case signedOut
    /// Includes temporary network and account lookup failures; never means signed out.
    case unavailable(String)
}

public struct ProviderCheckpoint: Codable, Equatable, Sendable {
    public var provider: String
    public var data: Data
    public init(provider: String, data: Data) { self.provider = provider; self.data = data }
}

public struct RemoteSnapshot: Codable, Equatable, Sendable {
    public var state: ListState
    public var revision: String?
    public init(state: ListState, revision: String?) { self.state = state; self.revision = revision }
}

public struct RemoteExchange: Sendable {
    public var snapshot: RemoteSnapshot?
    public var checkpoint: ProviderCheckpoint?
    public init(snapshot: RemoteSnapshot?, checkpoint: ProviderCheckpoint? = nil) {
        self.snapshot = snapshot; self.checkpoint = checkpoint
    }
}

public enum RemoteSyncError: Error, LocalizedError, Sendable {
    case revisionConflict
    case accountChanged
    case unavailable(String)
    public var errorDescription: String? {
        switch self {
        case .revisionConflict: return "Another device changed the list. Sync again to merge it."
        case .accountChanged: return "The sync account changed. Sync again to open its separate list."
        case .unavailable(let message): return message
        }
    }
}

/// A write is compare-and-swap: nil revision means create only if absent.
/// Account identity must be checked at the provider boundary, including after suspension.
/// Providers must not send restored pending writes without a new coordinator request.
public protocol RemoteSync: Sendable {
    var providerID: String { get }
    func account() async -> RemoteAccount
    func fetch(account: String, checkpoint: ProviderCheckpoint?) async throws -> RemoteExchange
    func publish(_ state: ListState, account: String, expecting revision: String?,
                 checkpoint: ProviderCheckpoint?) async throws -> RemoteExchange
    func requests() async -> AsyncStream<Void>
}

public struct PendingConflict: Codable, Equatable, Sendable {
    public var interruptedUpload: Bool?
    public var base: ListState?
    public var local: ListState
    public var remote: RemoteSnapshot
    public init(base: ListState?, local: ListState, remote: RemoteSnapshot) {
        self.base = base; self.local = local; self.remote = remote
    }
}

public struct OutgoingAttempt: Codable, Equatable, Sendable {
    public var state: ListState
    public var expectedRevision: String?
    public init(state: ListState, expectedRevision: String?) {
        self.state = state; self.expectedRevision = expectedRevision
    }
}

public struct AccountListState: Codable, Equatable, Sendable {
    public var state = ListState()
    public var outgoingAttempt: OutgoingAttempt?
    public var baseline: RemoteSnapshot?
    public var pending = false
    public var conflict: PendingConflict?
    public var checkpoint: ProviderCheckpoint?
    public var notice: String?
    public init(state: ListState = ListState()) { self.state = state }
}

/// One transaction contains every account partition and all restart information.
public struct LocalStoreState: Codable, Equatable, Sendable {
    public var activeAccount: String?
    public var adoptedLocalList = false
    public var local = AccountListState()
    public var accounts: [String: AccountListState] = [:]
    public init() {}
    public var current: AccountListState {
        get { activeAccount.flatMap { accounts[$0] } ?? local }
        set {
            if let activeAccount { accounts[activeAccount] = newValue }
            else { local = newValue }
        }
    }
    public func validate() throws {
        if let activeAccount, accounts[activeAccount] == nil { throw RuleError("Missing account list.") }
        for value in [local] + Array(accounts.values) {
            try Self.validate(value.state)
            if let attempt = value.outgoingAttempt { try Self.validate(attempt.state) }
            if let baseline = value.baseline { try Self.validate(baseline.state) }
            if let conflict = value.conflict {
                if let base = conflict.base { try Self.validate(base) }
                try Self.validate(conflict.local)
                try Self.validate(conflict.remote.state)
            }
        }
    }
    public static func validate(_ state: ListState) throws {
        try WorkItemRules.validate(state)
        try ListRules.validateSelection(state)
    }
}

/// save replaces the entire transaction or throws leaving the old transaction readable.
/// preserveRecovery must retain the previous bytes before replacing them.
public protocol LocalStorage: Sendable {
    func load() async throws -> LocalStoreState
    func save(_ lists: LocalStoreState, preserveRecovery: Bool) async throws
}
