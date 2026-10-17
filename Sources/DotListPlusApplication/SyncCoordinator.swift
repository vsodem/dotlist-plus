import DotListPlusCore
import Foundation

public struct CoordinatorSnapshot: Sendable {
    public var state: ListState
    public var scope: String
    public var generation: Int
    public var pending: Bool
    public var status: String
    public var conflicts: [MergeConflict]
    public var notice: String?
}

/// The gate spans awaits: actor isolation alone would allow a second mutation
/// to overwrite a save or a merge while the first operation is suspended.
public actor SyncCoordinator {
    private let storage: any LocalStorage
    private let remote: any RemoteSync
    private var lists = LocalStoreState()
    private var loaded = false
    private var generation = 0
    private var status = "Opening saved list…"
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(storage: any LocalStorage, remote: any RemoteSync) {
        self.storage = storage; self.remote = remote
    }

    public func requests() async -> AsyncStream<Void> { await remote.requests() }

    private func lock() async {
        if !locked { locked = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func unlock() {
        if waiters.isEmpty { locked = false }
        else { waiters.removeFirst().resume() }
    }
    private func save(_ next: LocalStoreState, recovery: Bool = false) async throws {
        try Task.checkCancellation()
        try next.validate()
        try await storage.save(next, preserveRecovery: recovery)
        lists = next
        generation += 1
    }
    private func requireLoaded() throws {
        guard loaded else { throw RuleError("Open or recover the saved list before making changes.") }
    }

    private var scope: String { lists.activeAccount ?? "local" }
    private func checkScope(_ expected: String?) throws {
        if let expected, expected != scope { throw RuleError("The account changed while you were editing. Open the list again before saving.") }
    }

    public func snapshot() -> CoordinatorSnapshot {
        let current = lists.current
        let conflicts: [MergeConflict]
        if let conflict = current.conflict {
            if conflict.interruptedUpload == true {
                conflicts = [MergeConflict(id: "list.interrupted", title: "An upload was interrupted and another device changed the list",
                    localDescription: "Keep this device’s complete list (\(conflict.local.workItems.count) work items).",
                    remoteDescription: "Keep the shared complete list (\(conflict.remote.state.workItems.count) work items).")]
            } else {
            conflicts = (try? ListMerge.merge(base: conflict.base, local: conflict.local,
                                              remote: conflict.remote.state).conflicts) ?? []
            }
        } else { conflicts = [] }
        return CoordinatorSnapshot(state: current.state, scope: scope, generation: generation, pending: current.pending, status: status,
                        conflicts: conflicts, notice: current.notice)
    }

    public func load() async throws -> CoordinatorSnapshot {
        await lock(); defer { unlock() }
        try Task.checkCancellation()
        let saved = try await storage.load()
        try saved.validate()
        lists = saved; loaded = true; generation += 1
        status = lists.current.pending ? "Changes saved on this device. Waiting to sync." : "Saved on this device."
        return snapshot()
    }

    public func apply(_ changes: [ListChange], expectedScope: String? = nil, expectedState: ListState? = nil) async throws -> CoordinatorSnapshot {
        await lock(); defer { unlock() }
        try Task.checkCancellation()
        try checkScope(expectedScope)
        try requireLoaded()
        guard lists.current.conflict == nil else { throw RuleError("Resolve the sync conflict in Settings before editing this list.") }
        if let expectedState, expectedState != lists.current.state {
            throw RuleError("The list changed while you were working. Review the current list or reopen the editor before saving again.")
        }
        var next = lists
        for change in changes { next.current.state = try ListRules.transition(next.current.state, change) }
        next.current.pending = true
        let erasing = changes.contains { if case .eraseCurrentList = $0 { return true }; return false }
        try await save(next, recovery: erasing)
        status = "Changes saved on this device. Waiting to sync."
        return snapshot()
    }

    public func replace(with state: ListState, notice: String? = nil, expectedScope: String? = nil, expectedState: ListState? = nil) async throws -> CoordinatorSnapshot {
        await lock(); defer { unlock() }
        try Task.checkCancellation()
        try checkScope(expectedScope)
        try LocalStoreState.validate(state)
        try requireLoaded()
        if let expectedState, expectedState != lists.current.state {
            throw RuleError("The list changed while the import confirmation was open. Review it before importing again.")
        }
        var next = lists
        if let conflict = next.current.conflict { next.current.baseline = conflict.remote }
        next.current.state = state
        next.current.conflict = nil
        next.current.outgoingAttempt = nil
        next.current.pending = true
        next.current.notice = notice ?? "Imported your list. A recovery copy was kept on this device."
        try await save(next, recovery: true)
        loaded = true
        status = "Imported list saved. Waiting to sync."
        return snapshot()
    }

    public func resolve(_ choices: [String: MergeChoice], expectedScope: String? = nil) async throws -> CoordinatorSnapshot {
        await lock(); defer { unlock() }
        try Task.checkCancellation()
        try checkScope(expectedScope)
        try requireLoaded()
        guard let conflict = lists.current.conflict else { return snapshot() }
        let result: MergeResult
        if conflict.interruptedUpload == true {
            guard let choice = choices["list.interrupted"] ?? choices["list.structure"] else {
                throw RuleError("Choose which complete list to keep after the interrupted upload.")
            }
            result = MergeResult(state: choice == .local ? conflict.local : conflict.remote.state, conflicts: [], notice: nil)
        } else {
            result = try ListMerge.merge(base: conflict.base, local: conflict.local,
                                         remote: conflict.remote.state, choices: choices)
        }
        guard let state = result.state, result.conflicts.isEmpty else {
            throw RuleError("Choose a version for every conflict. If the combined relationships are invalid, choose one complete list.")
        }
        var next = lists
        next.current.state = state
        next.current.baseline = conflict.remote
        next.current.outgoingAttempt = nil
        next.current.conflict = nil
        next.current.pending = state != conflict.remote.state
        next.current.notice = result.notice
        try await save(next, recovery: true)
        status = "Conflict choices saved. Waiting to sync."
        return snapshot()
    }

    public func sync() async throws -> CoordinatorSnapshot {
        await lock(); defer { unlock() }
        try Task.checkCancellation()
        try requireLoaded()
        do {
            let identity = await remote.account()
            let account: String
            switch identity {
            case .unavailable(let message):
                status = "Saved on this device. \(message)"; return snapshot()
            case .signedOut:
                if lists.activeAccount != nil {
                    var next = lists; next.activeAccount = nil
                    try await save(next)
                }
                status = "The sync account is signed out. This device's separate local list is open."
                return snapshot()
            case .available(let value): account = value
            }
            let key = remote.providerID + ":" + account
            if lists.activeAccount != key {
                var next = lists
                if next.accounts[key] == nil {
                    next.accounts[key] = next.adoptedLocalList ? AccountListState() : next.local
                    if !next.adoptedLocalList {
                        next.local = AccountListState()
                        next.adoptedLocalList = true
                    }
                }
                next.activeAccount = key
                try await save(next)
            }
            status = "Syncing…"
            for attempt in 0..<3 {
                do {
                    try await exchange(account: account)
                    return snapshot()
                } catch RemoteSyncError.revisionConflict where attempt < 2 {
                    continue
                }
            }
        } catch {
            status = "Changes remain saved on this device. Sync paused: \(error.localizedDescription)"
        }
        return snapshot()
    }

    private func checkAccount(_ account: String) async throws {
        try Task.checkCancellation()
        guard await remote.account() == .available(account) else { throw RemoteSyncError.accountChanged }
    }

    private func exchange(account: String) async throws {
        guard lists.current.conflict == nil else {
            status = "Sync needs your choices in Settings. Both versions are saved."
            return
        }
        let checkpoint = lists.current.checkpoint?.provider == remote.providerID ? lists.current.checkpoint : nil
        let fetched = try await remote.fetch(account: account, checkpoint: checkpoint)
        try await checkAccount(account)
        let shared = fetched.snapshot ?? RemoteSnapshot(state: ListState(), revision: nil)
        try LocalStoreState.validate(shared.state)
        var current = lists.current
        if let attempt = current.outgoingAttempt {
            if shared.state == attempt.state {
                current.baseline = shared
                current.outgoingAttempt = nil
            } else if shared.revision != attempt.expectedRevision {
                var next = lists
                var conflict = PendingConflict(base: current.baseline?.state, local: current.state, remote: shared)
                conflict.interruptedUpload = true
                next.current.conflict = conflict
                next.current.checkpoint = fetched.checkpoint
                try await save(next)
                status = "An interrupted upload needs your choices in Settings. Both versions are saved."
                return
            }
        }
        let result = try ListMerge.merge(base: current.baseline?.state, local: current.state, remote: shared.state)
        var next = lists
        next.current.checkpoint = fetched.checkpoint
        if !result.conflicts.isEmpty || result.state == nil {
            next.current.conflict = PendingConflict(base: current.baseline?.state, local: current.state, remote: shared)
            try await save(next)
            status = "Sync needs your choices in Settings. Both versions are saved."
            return
        }
        let merged = result.state!
        next.current.state = merged
        next.current.baseline = shared
        next.current.conflict = nil
        next.current.pending = merged != shared.state
        next.current.notice = result.notice ?? current.notice
        next.current.outgoingAttempt = next.current.pending ? OutgoingAttempt(state: merged, expectedRevision: shared.revision) : nil
        // Persist the merge and outbox before any network write.
        try await save(next)
        if next.current.pending {
            let sent: RemoteExchange
            do {
                sent = try await remote.publish(merged, account: account, expecting: shared.revision,
                                                checkpoint: fetched.checkpoint)
            } catch RemoteSyncError.revisionConflict {
                // A rejected conditional write is known not to have committed.
                next.current.outgoingAttempt = nil
                try await save(next)
                throw RemoteSyncError.revisionConflict
            }
            try await checkAccount(account)
            guard let confirmed = sent.snapshot, confirmed.state == merged, confirmed.revision != nil else {
                throw RuleError("The sync provider did not confirm the saved list.")
            }
            next.current.outgoingAttempt = nil
            next.current.baseline = confirmed
            next.current.pending = false
            next.current.checkpoint = sent.checkpoint
            try await save(next)
        }
        status = "Up to date."
    }
}
