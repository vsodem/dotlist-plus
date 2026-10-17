import XCTest
import DotListPlusCore
import DotListPlusApplication

actor TestStorage: LocalStorage {
    var lists = LocalStoreState()
    var fail = false
    func load() async throws -> LocalStoreState { lists }
    func save(_ lists: LocalStoreState, preserveRecovery: Bool) async throws {
        if fail { throw RuleError("Disk full") }
        try lists.validate()
        self.lists = lists
    }
    func failing(_ value: Bool) { fail = value }
}

actor FakeRemote: RemoteSync {
    nonisolated let providerID = "fake"
    var identity: RemoteAccount = .available("one")
    var cloud: [String: RemoteSnapshot] = [:]
    var online = true
    var loseResponse = false
    var afterPublish: (@Sendable () async -> Void)?
    var afterFetch: (@Sendable () async -> Void)?
    var rejectedWrites = 0
    var fetchCount = 0
    var publishCount = 0
    var receivedCheckpoints: [ProviderCheckpoint?] = []
    func afterPublishing(_ action: @escaping @Sendable () async -> Void) { afterPublish = action }
    func afterFetching(_ action: @escaping @Sendable () async -> Void) { afterFetch = action }
    func rejectWrites(_ count: Int) { rejectedWrites = count }
    func seed(_ snapshot: RemoteSnapshot, account: String) { cloud[account] = snapshot }
    func account() async -> RemoteAccount { identity }
    func setAccount(_ value: RemoteAccount) { identity = value }
    func setOnline(_ value: Bool) { online = value }
    func dropResponse() { loseResponse = true }
    func fetch(account: String, checkpoint: ProviderCheckpoint?) async throws -> RemoteExchange {
        try check(account)
        fetchCount += 1
        receivedCheckpoints.append(checkpoint)
        let result = RemoteExchange(snapshot: cloud[account], checkpoint: token(account))
        if let action = afterFetch { afterFetch = nil; await action() }
        return result
    }
    func publish(_ state: ListState, account: String, expecting revision: String?, checkpoint: ProviderCheckpoint?) async throws -> RemoteExchange {
        try check(account)
        publishCount += 1
        if rejectedWrites > 0 { rejectedWrites -= 1; throw RemoteSyncError.revisionConflict }
        guard cloud[account]?.revision == revision else { throw RemoteSyncError.revisionConflict }
        try LocalStoreState.validate(state)
        cloud[account] = RemoteSnapshot(state: state, revision: UUID().uuidString)
        if let action = afterPublish { afterPublish = nil; await action() }
        if loseResponse { loseResponse = false; throw RemoteSyncError.unavailable("Response lost") }
        return RemoteExchange(snapshot: cloud[account], checkpoint: token(account))
    }
    private func token(_ account: String) -> ProviderCheckpoint {
        ProviderCheckpoint(provider: providerID, data: Data(account.utf8))
    }
    func requests() async -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    private func check(_ id: String) throws {
        guard identity == .available(id) else { throw RemoteSyncError.accountChanged }
        guard online else { throw RemoteSyncError.unavailable("Offline") }
    }
}

final class CoordinatorTests: XCTestCase {
    func testOfflineSaveRestartAndUpload() async throws {
        let storage = TestStorage(), remote = FakeRemote()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load()
        _ = try await coordinator.sync()
        await remote.setOnline(false)
        let saved = try await coordinator.apply([.addWorkItem(WorkItem(id: "a", title: "A"))])
        XCTAssertEqual(saved.state.workItems.map(\.id), ["a"])
        _ = try await coordinator.sync()
        let restarted = SyncCoordinator(storage: storage, remote: remote)
        let loaded = try await restarted.load()
        XCTAssertEqual(loaded.state.workItems.map(\.id), ["a"])
        await remote.setOnline(true)
        let synced = try await restarted.sync()
        XCTAssertFalse(synced.pending)
        let cloud = try await remote.fetch(account: "one", checkpoint: nil)
        XCTAssertEqual(cloud.snapshot?.state.workItems.map(\.id), ["a"])
    }

    func testFailedSaveDoesNotPublishSuccess() async throws {
        let storage = TestStorage(), remote = FakeRemote()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load()
        await storage.failing(true)
        do { _ = try await coordinator.apply([.addWorkItem(WorkItem(id: "a", title: "A"))]); XCTFail() } catch { XCTAssertEqual(error as? RuleError, RuleError("Disk full")) }
        let view = await coordinator.snapshot()
        XCTAssertTrue(view.state.workItems.isEmpty)
        let saved = try await storage.load()
        XCTAssertEqual(saved.current.state, view.state)
    }

    func testLostUploadResponseIsSafeAfterRestart() async throws {
        let storage = TestStorage(), remote = FakeRemote()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load()
        _ = try await coordinator.apply([.addWorkItem(WorkItem(id: "a", title: "A"))])
        await remote.dropResponse()
        _ = try await coordinator.sync()
        let restarted = SyncCoordinator(storage: storage, remote: remote)
        _ = try await restarted.load()
        let view = try await restarted.sync()
        XCTAssertEqual(view.state.workItems.map(\.id), ["a"])
        XCTAssertFalse(view.pending)
        XCTAssertTrue(view.conflicts.isEmpty)
    }

    func testAccountsDoNotUploadEachOthersLists() async throws {
        let storage = TestStorage(), remote = FakeRemote()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load()
        _ = try await coordinator.apply([.addWorkItem(WorkItem(id: "a", title: "A"))])
        _ = try await coordinator.sync()
        await remote.setAccount(.available("two"))
        let other = try await coordinator.sync()
        XCTAssertTrue(other.state.workItems.isEmpty)
        _ = try await coordinator.apply([.addWorkItem(WorkItem(id: "b", title: "B"))])
        _ = try await coordinator.sync()
        await remote.setAccount(.available("one"))
        let restored = try await coordinator.sync()
        XCTAssertEqual(restored.state.workItems.map(\.id), ["a"])
        await remote.setAccount(.signedOut)
        let local = try await coordinator.sync()
        XCTAssertTrue(local.state.workItems.isEmpty)
    }

    func testTwoDevicesMergeAdditionsAndResolveDeletion() async throws {
        let remote = FakeRemote()
        let a = SyncCoordinator(storage: TestStorage(), remote: remote)
        let bStorage = TestStorage()
        let b = SyncCoordinator(storage: bStorage, remote: remote)
        _ = try await a.load(); _ = try await b.load()
        _ = try await a.apply([.addWorkItem(WorkItem(id: "a", title: "A"))])
        _ = try await a.sync(); _ = try await b.sync()
        _ = try await a.apply([.addWorkItem(WorkItem(id: "b", title: "B"))])
        _ = try await b.apply([.addWorkItem(WorkItem(id: "c", title: "C"))])
        _ = try await a.sync()
        let merged = try await b.sync()
        XCTAssertEqual(Set(merged.state.workItems.map(\.id)), ["a", "b", "c"])
        _ = try await a.sync()
        _ = try await a.apply([.deleteWorkItem("a")])
        _ = try await b.apply([.renameWorkItem("a", "Edited")])
        _ = try await a.sync()
        let conflict = try await b.sync()
        XCTAssertFalse(conflict.conflicts.isEmpty)
        let restart = SyncCoordinator(storage: bStorage, remote: remote)
        let restored = try await restart.load()
        XCTAssertEqual(restored.conflicts, conflict.conflicts)
        let choices = Dictionary(uniqueKeysWithValues: restored.conflicts.map { ($0.id, MergeChoice.local) })
        _ = try await restart.resolve(choices)
        let resolved = try await restart.sync()
        XCTAssertTrue(resolved.conflicts.isEmpty)
        XCTAssertEqual(resolved.state.workItem("a")?.title, "Edited")
    }

    func testImportAndErasePropagate() async throws {
        let remote = FakeRemote()
        let a = SyncCoordinator(storage: TestStorage(), remote: remote)
        let b = SyncCoordinator(storage: TestStorage(), remote: remote)
        _ = try await a.load(); _ = try await b.load()
        _ = try await a.sync(); _ = try await b.sync()
        var imported = ListState()
        imported.workItems = [WorkItem(id: "new", title: "Imported")]; imported.actionOrder = ["new"]
        _ = try await a.replace(with: imported)
        _ = try await a.sync()
        let downloaded = try await b.sync()
        XCTAssertEqual(downloaded.state, imported)
        _ = try await b.apply([.eraseCurrentList]); _ = try await b.sync()
        let erased = try await a.sync()
        XCTAssertTrue(erased.state.workItems.isEmpty)
    }
    func testStaleEditorCannotWriteIntoDifferentAccount() async throws {
        let remote = FakeRemote()
        let coordinator = SyncCoordinator(storage: TestStorage(), remote: remote)
        _ = try await coordinator.load()
        let first = try await coordinator.sync()
        await remote.setAccount(.available("two"))
        _ = try await coordinator.sync()
        do {
            _ = try await coordinator.apply([.addWorkItem(WorkItem(id: "old", title: "Old account draft"))], expectedScope: first.scope)
            XCTFail("An old account's editor must not save into the new account")
        } catch { XCTAssertEqual(error as? RuleError, RuleError("The account changed while you were editing. Open the list again before saving.")) }
        let current = await coordinator.snapshot()
        XCTAssertTrue(current.state.workItems.isEmpty)
    }

    func testUnknownAccountDoesNotSwitchOrLoseOfflineEdits() async throws {
        let remote = FakeRemote(), storage = TestStorage()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load(); _ = try await coordinator.sync()
        _ = try await coordinator.apply([.addWorkItem(WorkItem(id: "a", title: "Offline"))])
        await remote.setAccount(.unavailable("Cannot determine account"))
        let unavailable = try await coordinator.sync()
        XCTAssertEqual(unavailable.state.workItems.map(\.id), ["a"])
        XCTAssertTrue(unavailable.pending)
        await remote.setAccount(.available("one"))
        let restored = try await coordinator.sync()
        XCTAssertEqual(restored.state.workItems.map(\.id), ["a"])
        XCTAssertFalse(restored.pending)
    }

    func testUnconfirmedUploadDoesNotResurrectTaskDeletedByAnotherDevice() async throws {
        let remote = FakeRemote(), storage = TestStorage()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load()
        _ = try await coordinator.apply([.addWorkItem(WorkItem(id: "a", title: "A"))])
        await remote.dropResponse()
        _ = try await coordinator.sync()
        let uploaded = try await remote.fetch(account: "one", checkpoint: nil)
        _ = try await remote.publish(ListState(), account: "one", expecting: uploaded.snapshot?.revision, checkpoint: nil)
        let restart = SyncCoordinator(storage: storage, remote: remote)
        _ = try await restart.load()
        let uncertain = try await restart.sync()
        XCTAssertEqual(uncertain.conflicts.map(\.id), ["list.interrupted"])
        let cloud = try await remote.fetch(account: "one", checkpoint: nil)
        XCTAssertTrue(try XCTUnwrap(cloud.snapshot).state.workItems.isEmpty)
        _ = try await restart.resolve(["list.interrupted": .remote])
        let resolved = try await restart.sync()
        XCTAssertTrue(resolved.state.workItems.isEmpty)
    }

    func testConflictingVersionsStayFixedUntilResolution() async throws {
        let remote = FakeRemote()
        let a = SyncCoordinator(storage: TestStorage(), remote: remote)
        let b = SyncCoordinator(storage: TestStorage(), remote: remote)
        _ = try await a.load(); _ = try await b.load()
        _ = try await a.apply([.addWorkItem(WorkItem(id: "a", title: "Original"))])
        _ = try await a.sync(); _ = try await b.sync()
        _ = try await a.apply([.renameWorkItem("a", "First remote edit")])
        _ = try await b.apply([.renameWorkItem("a", "Local edit")])
        _ = try await a.sync()
        let first = try await b.sync()
        _ = try await a.apply([.renameWorkItem("a", "Second remote edit")]); _ = try await a.sync()
        let repeated = try await b.sync()
        XCTAssertEqual(repeated.conflicts, first.conflicts)
        _ = try await b.resolve(Dictionary(uniqueKeysWithValues: first.conflicts.map { ($0.id, MergeChoice.remote) }))
        let latest = try await b.sync()
        XCTAssertEqual(latest.state.workItem("a")?.title, "Second remote edit")
    }

    func testLocalAcknowledgementFailureRecoversWithoutDuplicateUpload() async throws {
        let remote = FakeRemote(), storage = TestStorage()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load()
        _ = try await coordinator.apply([.addWorkItem(WorkItem(id: "a", title: "A"))])
        await remote.afterPublishing { await storage.failing(true) }
        let interrupted = try await coordinator.sync()
        XCTAssertTrue(interrupted.pending)
        let first = try await remote.fetch(account: "one", checkpoint: nil)
        await storage.failing(false)
        let restarted = SyncCoordinator(storage: storage, remote: remote)
        _ = try await restarted.load()
        let recovered = try await restarted.sync()
        let final = try await remote.fetch(account: "one", checkpoint: nil)
        XCTAssertFalse(recovered.pending)
        XCTAssertEqual(recovered.state.workItems.map(\.id), ["a"])
        XCTAssertEqual(final.snapshot?.revision, first.snapshot?.revision)
    }

    func testInvalidRemoteNeverReplacesSavedList() async throws {
        let remote = FakeRemote(), storage = TestStorage()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load()
        _ = try await coordinator.apply([.addWorkItem(WorkItem(id: "a", title: "A"))])
        let before = try await coordinator.sync()
        var invalid = before.state
        invalid.workItems[0].prerequisiteIDs = ["missing"]
        await remote.seed(RemoteSnapshot(state: invalid, revision: "bad"), account: "one")
        let after = try await coordinator.sync()
        XCTAssertEqual(after.state, before.state)
        XCTAssertTrue(after.status.contains("paused"))
        let stored = try await storage.load()
        XCTAssertEqual(stored.current.state, before.state)
    }

    /// Reusable provider contract; run the same checks against any isolated test account.
    func checkRemoteContract(_ remote: any RemoteSync, account: String) async throws {
        let initial = try await remote.fetch(account: account, checkpoint: nil)
        XCTAssertNil(initial.snapshot)
        var state = ListState()
        state.workItems = [WorkItem(id: "contract", title: "Contract")]; state.actionOrder = ["contract"]
        let first = try await remote.publish(state, account: account, expecting: nil, checkpoint: nil)
        let revision = try XCTUnwrap(first.snapshot?.revision)
        do {
            _ = try await remote.publish(ListState(), account: account, expecting: nil, checkpoint: first.checkpoint)
            XCTFail("Create with a stale absent revision must fail")
        } catch RemoteSyncError.revisionConflict {}
        let retained = try await remote.fetch(account: account, checkpoint: first.checkpoint)
        XCTAssertEqual(retained.snapshot?.state, state)
        XCTAssertEqual(retained.snapshot?.revision, revision)
        let erased = try await remote.publish(ListState(), account: account, expecting: revision, checkpoint: retained.checkpoint)
        do {
            _ = try await remote.publish(state, account: account, expecting: revision, checkpoint: first.checkpoint)
            XCTFail("Stale update must not resurrect erased work")
        } catch RemoteSyncError.revisionConflict {}
        let final = try await remote.fetch(account: account, checkpoint: erased.checkpoint)
        XCTAssertEqual(final.snapshot?.state, ListState())
        XCTAssertEqual(final.snapshot?.revision, erased.snapshot?.revision)
    }

    func testRemoteRevisionContract() async throws {
        try await checkRemoteContract(FakeRemote(), account: "one")
    }

    func testConcurrentActionsAreSerializedWithoutLostUpdates() async throws {
        let coordinator = SyncCoordinator(storage: TestStorage(), remote: FakeRemote())
        _ = try await coordinator.load()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    _ = try await coordinator.apply([.addWorkItem(WorkItem(id: "\(index)", title: "Task \(index)"))])
                }
            }
            try await group.waitForAll()
        }
        let final = await coordinator.snapshot()
        XCTAssertEqual(final.state.workItems.count, 20)
        XCTAssertEqual(Set(final.state.actionOrder).count, 20)
    }

    func testStaleSelectionCannotCompleteDifferentNextTask() async throws {
        let remote = FakeRemote()
        let coordinator = SyncCoordinator(storage: TestStorage(), remote: remote)
        _ = try await coordinator.load()
        _ = try await coordinator.apply([.addWorkItem(WorkItem(id: "a", title: "A")),
                                         .addWorkItem(WorkItem(id: "b", title: "B")), .makeUrgent("a")])
        let displayed = try await coordinator.sync()
        let changed = try ListRules.transition(displayed.state, .makeUrgent("b"))
        let fetched = try await remote.fetch(account: "one", checkpoint: nil)
        _ = try await remote.publish(changed, account: "one", expecting: fetched.snapshot?.revision, checkpoint: nil)
        _ = try await coordinator.sync()
        do {
            _ = try await coordinator.apply([.completeNextAction], expectedState: displayed.state)
            XCTFail("Done for A must not complete B")
        } catch { XCTAssertEqual(error as? RuleError, RuleError("The list changed while you were working. Review the current list or reopen the editor before saving again.")) }
        let result = await coordinator.snapshot()
        XCTAssertEqual(result.state.nextAction?.id, "b")
        XCTAssertNil(result.state.workItem("b")?.completedAt)
    }

    func testEditorOpeningSnapshotProtectsDownloadedRename() async throws {
        let remote = FakeRemote()
        let coordinator = SyncCoordinator(storage: TestStorage(), remote: remote)
        _ = try await coordinator.load()
        _ = try await coordinator.apply([.addWorkItem(WorkItem(id: "a", title: "Original"))])
        let opening = try await coordinator.sync()
        let renamed = try ListRules.transition(opening.state, .renameWorkItem("a", "Remote title"))
        let fetched = try await remote.fetch(account: "one", checkpoint: nil)
        _ = try await remote.publish(renamed, account: "one", expecting: fetched.snapshot?.revision, checkpoint: nil)
        _ = try await coordinator.sync()
        do {
            _ = try await coordinator.apply([.renameWorkItem("a", "Original")], expectedState: opening.state)
            XCTFail("Stale editor must not restore the old title")
        } catch { XCTAssertEqual(error as? RuleError, RuleError("The list changed while you were working. Review the current list or reopen the editor before saving again.")) }
        let result = await coordinator.snapshot()
        XCTAssertEqual(result.state.workItem("a")?.title, "Remote title")
    }

}

extension CoordinatorTests {
    func testCancelledCommandDoesNotCommit() async throws {
        let storage = TestStorage(), remote = FakeRemote()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load()
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await coordinator.apply([.addWorkItem(WorkItem(id: "cancelled", title: "Cancelled"))])
        }
        do { _ = try await operation.value; XCTFail("Cancelled commands must not commit") } catch is CancellationError {} catch { XCTFail("Wrong error: \(error)") }
        let snapshot = await coordinator.snapshot()
        XCTAssertTrue(snapshot.state.workItems.isEmpty)
    }

    func testMergeCreatedCycleRetainsInputsAndResolvesAfterRestart() async throws {
        let storage = TestStorage(), remote = FakeRemote()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load()
        _ = try await coordinator.apply([.addWorkItem(WorkItem(id: "a", title: "A")), .addWorkItem(WorkItem(id: "b", title: "B"))])
        let base = try await coordinator.sync()
        let local = try await coordinator.apply([.updateRelationships("a", project: nil, parent: nil, prerequisites: ["b"])])
        let other = try ListRules.transition(base.state, .updateRelationships("b", project: nil, parent: nil, prerequisites: ["a"]))
        await remote.seed(RemoteSnapshot(state: other, revision: "new"), account: "one")
        let conflict = try await coordinator.sync()
        XCTAssertEqual(conflict.state, local.state)
        XCTAssertEqual(conflict.conflicts.map(\.id), ["list.structure"])
        let saved = try await storage.load()
        XCTAssertEqual(saved.current.conflict?.local, local.state)
        XCTAssertEqual(saved.current.conflict?.remote.state, other)
        let untouched = try await remote.fetch(account: "one", checkpoint: nil)
        XCTAssertEqual(untouched.snapshot?.state, other)
        let restarted = SyncCoordinator(storage: storage, remote: remote)
        _ = try await restarted.load()
        _ = try await restarted.resolve(["list.structure": .local])
        let resolved = try await restarted.sync()
        XCTAssertTrue(resolved.conflicts.isEmpty)
        XCTAssertFalse(resolved.pending)
        XCTAssertEqual(resolved.state, local.state)
        let shared = try await remote.fetch(account: "one", checkpoint: nil)
        XCTAssertEqual(shared.snapshot?.state, local.state)
    }
}

extension CoordinatorTests {
    func testPortableReplacementRequiresLoadedStore() async throws {
        let coordinator = SyncCoordinator(storage: TestStorage(), remote: FakeRemote())
        do { _ = try await coordinator.replace(with: ListState()); XCTFail("Load must succeed before replacement") } catch { XCTAssertEqual(error as? RuleError, RuleError("Open or recover the saved list before making changes.")) }
    }
}

extension CoordinatorTests {
    func testStaleImportCannotReplaceUnseenEdits() async throws {
        let coordinator = SyncCoordinator(storage: TestStorage(), remote: FakeRemote())
        let displayed = try await coordinator.load()
        let latest = try await coordinator.apply([.addWorkItem(WorkItem(id: "new", title: "New work"))])
        do {
            _ = try await coordinator.replace(with: ListState(), expectedScope: displayed.scope, expectedState: displayed.state)
            XCTFail("Stale import must not remove unseen work")
        } catch { XCTAssertEqual(error as? RuleError, RuleError("The list changed while the import confirmation was open. Review it before importing again.")) }
        let after = await coordinator.snapshot()
        XCTAssertEqual(after.state, latest.state)
        do {
            _ = try await coordinator.apply([.eraseCurrentList], expectedScope: displayed.scope, expectedState: displayed.state)
            XCTFail("Stale erase must not remove unseen work")
        } catch { XCTAssertEqual(error as? RuleError, RuleError("The list changed while you were working. Review the current list or reopen the editor before saving again.")) }
    }
}

extension CoordinatorTests {
    func testRevisionConflictsRefetchAndStopAfterThreeAttempts() async throws {
        for rejected in [2, 4] {
            let remote = FakeRemote(), storage = TestStorage()
            let coordinator = SyncCoordinator(storage: storage, remote: remote)
            _ = try await coordinator.load()
            _ = try await coordinator.apply([.addWorkItem(WorkItem(id: "a", title: "A"))])
            await remote.rejectWrites(rejected)
            let result = try await coordinator.sync()
            let fetches = await remote.fetchCount, writes = await remote.publishCount
            XCTAssertEqual(fetches, 3)
            XCTAssertEqual(writes, 3)
            XCTAssertEqual(result.pending, rejected > 2)
            let saved = try await storage.load()
            XCTAssertEqual(saved.current.state.workItems.map(\.id), ["a"])
            XCTAssertNil(saved.current.outgoingAttempt, "Rejected writes are known not to have committed")
            if rejected > 2 {
                await remote.rejectWrites(0)
                let retried = try await coordinator.sync()
                XCTAssertFalse(retried.pending)
            }
        }
    }

    func testCancellationAfterFetchDoesNotMergeOrUpload() async throws {
        let remote = FakeRemote(), storage = TestStorage()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load(); _ = try await coordinator.sync()
        let local = try await coordinator.apply([.addWorkItem(WorkItem(id: "local", title: "Local"))])
        let shared = try ListRules.transition(ListState(), .addWorkItem(WorkItem(id: "remote", title: "Remote")))
        await remote.seed(RemoteSnapshot(state: shared, revision: "remote-1"), account: "one")
        await remote.afterFetching { withUnsafeCurrentTask { $0?.cancel() } }
        let operation = Task { try await coordinator.sync() }
        let cancelled = try await operation.value
        XCTAssertEqual(cancelled.state, local.state)
        XCTAssertTrue(cancelled.pending)
        let saved = try await storage.load(), writes = await remote.publishCount
        XCTAssertEqual(saved.current.state, local.state)
        XCTAssertEqual(writes, 0)
        let retried = try await coordinator.sync()
        XCTAssertEqual(Set(retried.state.workItems.map(\.id)), ["local", "remote"])
        XCTAssertFalse(retried.pending)
    }

    func testAccountChangeDuringFetchRejectsResponse() async throws {
        let remote = FakeRemote(), storage = TestStorage()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load(); _ = try await coordinator.sync()
        let local = try await coordinator.apply([.addWorkItem(WorkItem(id: "a", title: "A"))])
        await remote.afterFetching { await remote.setAccount(.available("two")) }
        let result = try await coordinator.sync()
        XCTAssertEqual(result.scope, "fake:one")
        XCTAssertEqual(result.state, local.state)
        let writes = await remote.publishCount
        XCTAssertEqual(writes, 0)
        let other = try await coordinator.sync()
        XCTAssertEqual(other.scope, "fake:two")
        XCTAssertTrue(other.state.workItems.isEmpty)
        let saved = try await storage.load()
        XCTAssertEqual(saved.accounts["fake:one"]?.state, local.state)
        XCTAssertEqual(saved.accounts["fake:one"]?.pending, true)
    }

    func testCheckpointsSurviveRestartAndStayInTheirProviderAndAccount() async throws {
        let remote = FakeRemote(), storage = TestStorage()
        var lists = LocalStoreState()
        lists.adoptedLocalList = true
        lists.activeAccount = "fake:one"
        var first = AccountListState()
        first.checkpoint = ProviderCheckpoint(provider: "other-provider", data: Data([99]))
        lists.accounts["fake:one"] = first
        try await storage.save(lists, preserveRecovery: false)
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load(); _ = try await coordinator.sync()
        let restarted = SyncCoordinator(storage: storage, remote: remote)
        _ = try await restarted.load(); _ = try await restarted.sync()
        await remote.setAccount(.available("two")); _ = try await restarted.sync()
        await remote.setAccount(.available("one")); _ = try await restarted.sync()
        let received = await remote.receivedCheckpoints
        XCTAssertEqual(received, [nil, ProviderCheckpoint(provider: "fake", data: Data("one".utf8)),
                                  nil, ProviderCheckpoint(provider: "fake", data: Data("one".utf8))])
        let saved = try await storage.load()
        XCTAssertEqual(saved.accounts["fake:two"]?.checkpoint?.data, Data("two".utf8))
    }

    func testCancellationAfterAtomicSaveStillPublishesDurableSnapshot() async throws {
        let storage = CancellingStorage()
        let coordinator = SyncCoordinator(storage: storage, remote: FakeRemote())
        _ = try await coordinator.load()
        let operation = Task { try await coordinator.apply([.addWorkItem(WorkItem(id: "a", title: "A"))]) }
        let committed = try await operation.value
        let saved = try await storage.load(), visible = await coordinator.snapshot()
        XCTAssertEqual(committed.state.workItems.map(\.id), ["a"])
        XCTAssertEqual(visible.state, saved.current.state)
        XCTAssertEqual(committed.state, saved.current.state)
    }
}

private actor CancellingStorage: LocalStorage {
    private var lists = LocalStoreState()
    func load() async throws -> LocalStoreState { lists }
    func save(_ lists: LocalStoreState, preserveRecovery: Bool) async throws {
        self.lists = lists
        withUnsafeCurrentTask { $0?.cancel() }
    }
}
