import DotListPlusCore
import DotListPlusApplication
import CloudKit
import Foundation
import Network

/// CKSyncEngine tracks incoming changes. Publication is a single conditional save:
/// no outgoing engine queue can replay a list after its coordinator request ends.
public actor CloudKitSync: RemoteSync, CKSyncEngineDelegate {
    public nonisolated let providerID = ProductIdentity.providerID
    private let container = CKContainer(identifier: ProductIdentity.cloudContainerID)
    private var database: CKDatabase { container.privateCloudDatabase }
    private var engine: CKSyncEngine?
    private var engineAccount: String?
    private var serialization: CKSyncEngine.State.Serialization?
    private var accountGeneration = 0
    private var listeners: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var accountObserver: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var networkMonitor: NWPathMonitor?
    private var connected: Bool?

    private struct Checkpoint: Codable {
        let version: Int
        let account: String
        let engine: CKSyncEngine.State.Serialization?
    }

    private struct Revision: Codable {
        let account: String
        let changeTag: String
    }

    public init() {}

    deinit {
        accountObserver?.cancel()
        retry?.cancel()
        networkMonitor?.cancel()
        for listener in listeners.values { listener.finish() }
    }

    public func account() async -> RemoteAccount {
        let generation = accountGeneration
        do {
            let status = try await container.accountStatus()
            guard generation == accountGeneration else {
                return .unavailable("The iCloud account is changing. Try syncing again.")
            }
            switch status {
            case .available:
                let user = try await container.userRecordID()
                guard generation == accountGeneration else {
                    return .unavailable("The iCloud account is changing. Try syncing again.")
                }
                return .available(user.recordName)
            case .noAccount: return .signedOut
            case .restricted: return .unavailable("iCloud access is restricted on this device.")
            case .couldNotDetermine, .temporarilyUnavailable:
                return .unavailable("iCloud is temporarily unavailable. Your list is saved on this device.")
            @unknown default: return .unavailable("iCloud is unavailable.")
            }
        } catch {
            scheduleRetry(for: error)
            return .unavailable(error.localizedDescription)
        }
    }

    public func fetch(account: String, checkpoint: ProviderCheckpoint?) async throws -> RemoteExchange {
        let generation = accountGeneration
        do {
            try await verifyAccount(account, generation: generation)
            let engine = prepareEngine(account: account, checkpoint: checkpoint)
            do {
                try await engine.fetchChanges(.init(scope: .zoneIDs([zoneID(account)])))
            } catch where isAbsent(error) {
                // A new account has no zone until its first explicit publication.
            }
            try await verifyAccount(account, generation: generation)
            // Always read the entire record, even when the engine's checkpoint says
            // there are no changes. Its tokens never substitute for a saved snapshot.
            let record = try await readRecord(account: account, generation: generation)
            let snapshot = try record.map { try decode($0, account: account) }
            return try exchange(snapshot, account: account)
        } catch {
            try await verifyAccount(account, generation: generation)
            throw providerError(error)
        }
    }

    public func publish(_ state: ListState, account: String, expecting revision: String?,
                 checkpoint: ProviderCheckpoint?) async throws -> RemoteExchange {
        let generation = accountGeneration
        do {
            try LocalStoreState.validate(state)
            try await verifyAccount(account, generation: generation)
            _ = prepareEngine(account: account, checkpoint: checkpoint)
            let existing = try await readRecord(account: account, generation: generation)
            let expectedTag = try revision.map { try decodeRevision($0, account: account) }
            guard existing?.recordChangeTag == expectedTag else { throw RemoteSyncError.revisionConflict }
            if let existing { _ = try CloudSnapshotCodec.decodeRecord(existing, account: account, recordID: recordID(account)) }

            if existing == nil {
                try await verifyAccount(account, generation: generation)
                _ = try await database.save(CKRecordZone(zoneID: zoneID(account)))
                try await verifyAccount(account, generation: generation)
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
            defer { try? FileManager.default.removeItem(at: url) }
            let record = try CloudSnapshotCodec.preparePublication(state, existing: existing, expectedTag: expectedTag,
                account: account, recordID: recordID(account), assetURL: url)
            try await verifyAccount(account, generation: generation)
            let result = try await database.modifyRecords(saving: [record], deleting: [],
                                                          savePolicy: .ifServerRecordUnchanged, atomically: true)
            try await verifyAccount(account, generation: generation)
            guard let saved = result.saveResults[record.recordID] else {
                throw RemoteSyncError.unavailable("iCloud did not confirm saving the list.")
            }
            let snapshot = try decode(saved.get(), account: account)
            return try exchange(snapshot, account: account)
        } catch {
            try await verifyAccount(account, generation: generation)
            throw providerError(error)
        }
    }

    public func requests() async -> AsyncStream<Void> {
        startObserving()
        let id = UUID()
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        listeners[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeListener(id) }
        }
        return pair.stream
    }

    private func zoneID(_ account: String) -> CKRecordZone.ID {
        // Pin the actual owner, rather than the "current user" alias. CloudKit then
        // rejects an in-flight write if a different account becomes active.
        CKRecordZone.ID(zoneName: ProductIdentity.cloudZone, ownerName: account)
    }

    private func recordID(_ account: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "complete-list", zoneID: zoneID(account))
    }

    @discardableResult
    private func verifyAccount(_ expected: String, generation: Int? = nil) async throws -> Int {
        try Task.checkCancellation()
        let before = accountGeneration
        let current = await account()
        guard before == accountGeneration, generation == nil || generation == accountGeneration else {
            throw RemoteSyncError.accountChanged
        }
        switch current {
        case .available(let current) where current == expected: return before
        case .unavailable(let message): throw RemoteSyncError.unavailable(message)
        default: throw RemoteSyncError.accountChanged
        }
    }

    private func readRecord(account: String, generation: Int) async throws -> CKRecord? {
        try await verifyAccount(account, generation: generation)
        do {
            let record = try await database.record(for: recordID(account))
            try await verifyAccount(account, generation: generation)
            return record
        } catch {
            try await verifyAccount(account, generation: generation)
            if isAbsent(error) { return nil }
            throw error
        }
    }

    private func decode(_ record: CKRecord, account: String) throws -> RemoteSnapshot {
        let state = try CloudSnapshotCodec.decodeRecord(record, account: account, recordID: recordID(account))
        guard let tag = record.recordChangeTag else {
            throw RemoteSyncError.unavailable("The iCloud list has no revision. Your local list was kept.")
        }
        let revision = try JSONEncoder().encode(Revision(account: account, changeTag: tag)).base64EncodedString()
        return RemoteSnapshot(state: state, revision: revision)
    }

    private func decodeRevision(_ value: String, account: String) throws -> String {
        guard let data = Data(base64Encoded: value),
              let revision = try? JSONDecoder().decode(Revision.self, from: data),
              revision.account == account else { throw RemoteSyncError.revisionConflict }
        return revision.changeTag
    }

    private func exchange(_ snapshot: RemoteSnapshot?, account: String) throws -> RemoteExchange {
        let value = Checkpoint(version: 1, account: account, engine: serialization)
        return RemoteExchange(snapshot: snapshot, checkpoint: ProviderCheckpoint(provider: providerID,
            data: try JSONEncoder().encode(value)))
    }

    private func prepareEngine(account: String, checkpoint: ProviderCheckpoint?) -> CKSyncEngine {
        if engineAccount == account, let engine { return engine }
        let oldEngine = engine
        engine = nil
        engineAccount = account
        serialization = nil
        if let oldEngine { Task { await oldEngine.cancelOperations() } }
        if let checkpoint, checkpoint.provider == providerID,
           let saved = try? JSONDecoder().decode(Checkpoint.self, from: checkpoint.data),
           saved.version == 1, saved.account == account {
            serialization = saved.engine
        }
        var configuration = CKSyncEngine.Configuration(database: database,
            stateSerialization: serialization, delegate: self)
        // Inspect a restored checkpoint with scheduling disabled before trusting it.
        // Old queued saves OR zone deletions must never reach an automatic engine.
        configuration.automaticallySync = false
        let restored = CKSyncEngine(configuration)
        if !restored.state.pendingRecordZoneChanges.isEmpty || !restored.state.pendingDatabaseChanges.isEmpty {
            serialization = nil
        }
        configuration.stateSerialization = serialization
        configuration.automaticallySync = true
        let active = CKSyncEngine(configuration)
        engine = active
        return active
    }

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine, let expected = engineAccount else { return }
        if case .accountChange(let change) = event {
            // A fresh engine reports its initial sign-in. Replacing it for that
            // event would create an endless cycle of fresh engines and sign-ins.
            if case .signIn(let current) = change.changeType, current.recordName == expected {
                guard (try? await verifyAccount(expected)) != nil, engine === syncEngine else { return }
                return
            }
            accountDidChange()
            return
        }
        guard (try? await verifyAccount(expected)) != nil, engine === syncEngine else { return }
        switch event {
        case .stateUpdate(let update): serialization = update.stateSerialization
        case .fetchedRecordZoneChanges(let changes):
            if changes.modifications.contains(where: { $0.record.recordID == recordID(expected) }) ||
                changes.deletions.contains(where: { $0.recordID == recordID(expected) }) { signal() }
        case .fetchedDatabaseChanges(let changes):
            if changes.deletions.contains(where: { $0.zoneID == zoneID(expected) }) { signal() }
        case .didFetchRecordZoneChanges(let result):
            if let error = result.error { scheduleRetry(for: error) }
        default: break
        }
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                  syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        // Only publish() may send a list, with its freshly verified revision.
        nil
    }

    public func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext,
                                syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        guard engine === syncEngine, let expected = engineAccount,
              (try? await verifyAccount(expected)) != nil, engine === syncEngine else {
            return .init(scope: .zoneIDs([]))
        }
        return .init(scope: .zoneIDs([zoneID(expected)]))
    }

    private func startObserving() {
        guard accountObserver == nil else { return }
        accountObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                guard !Task.isCancelled else { return }
                await self?.accountDidChange()
            }
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.connectionChanged(path.status == .satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "DotListPlus.iCloud.connection"))
        networkMonitor = monitor
    }

    private func accountDidChange() {
        accountGeneration += 1
        let oldEngine = engine
        engine = nil
        engineAccount = nil
        serialization = nil
        retry?.cancel()
        retry = nil
        // Never await engine operations within its serial delegate callback.
        if let oldEngine { Task { await oldEngine.cancelOperations() } }
        signal()
    }

    private func connectionChanged(_ available: Bool) {
        let previous = connected
        connected = available
        if previous != available { signal() }
    }

    private func signal() { for listener in listeners.values { listener.yield(()) } }
    private func removeListener(_ id: UUID) { listeners[id] = nil }

    private func isAbsent(_ error: Error) -> Bool {
        guard let error = error as? CKError else { return false }
        if error.code == .partialFailure, let errors = error.partialErrorsByItemID, !errors.isEmpty {
            return errors.values.allSatisfy { isAbsent($0) }
        }
        return error.code == .unknownItem || error.code == .zoneNotFound || error.code == .userDeletedZone
    }

    private func providerError(_ error: Error) -> Error {
        if let error = error as? RemoteSyncError { return error }
        if let cloud = error as? CKError {
            if cloud.code == .serverRecordChanged || isAbsent(cloud) { return RemoteSyncError.revisionConflict }
            if cloud.code == .partialFailure,
               let conflict = cloud.partialErrorsByItemID?.values.first(where: {
                   ($0 as? CKError)?.code == .serverRecordChanged
               }) { return providerError(conflict) }
            scheduleRetry(for: cloud)
        }
        return RemoteSyncError.unavailable(error.localizedDescription)
    }

    private func scheduleRetry(for error: Error) {
        guard retry == nil, let cloud = error as? CKError else { return }
        switch cloud.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            let delay = max(5, cloud.retryAfterSeconds ?? 30)
            retry = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                await self?.retryReady()
            }
        default: break
        }
    }

    private func retryReady() { retry = nil; signal() }
}
