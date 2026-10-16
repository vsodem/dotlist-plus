import XCTest
@testable import DotListCore

actor TestStorage: LocalStorage {
    var lists = StoredLists()
    var fail = false
    func load() async throws -> StoredLists { lists }
    func save(_ lists: StoredLists, preserveRecovery: Bool) async throws {
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
    func afterPublishing(_ action: @escaping @Sendable () async -> Void) { afterPublish = action }
    func seed(_ snapshot: RemoteSnapshot, account: String) { cloud[account] = snapshot }
    func account() async -> RemoteAccount { identity }
    func setAccount(_ value: RemoteAccount) { identity = value }
    func setOnline(_ value: Bool) { online = value }
    func dropResponse() { loseResponse = true }
    func fetch(account: String, checkpoint: ProviderCheckpoint?) async throws -> RemoteExchange {
        try check(account)
        return RemoteExchange(snapshot: cloud[account])
    }
    func publish(_ state: AppState, account: String, expecting revision: String?, checkpoint: ProviderCheckpoint?) async throws -> RemoteExchange {
        try check(account)
        guard cloud[account]?.revision == revision else { throw RemoteSyncError.revisionConflict }
        try StoredLists.validate(state)
        cloud[account] = RemoteSnapshot(state: state, revision: UUID().uuidString)
        if let action = afterPublish { afterPublish = nil; await action() }
        if loseResponse { loseResponse = false; throw RemoteSyncError.unavailable("Response lost") }
        return RemoteExchange(snapshot: cloud[account])
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
        let saved = try await coordinator.apply([.addTask(WorkTask(id: "a", title: "A"))])
        XCTAssertEqual(saved.state.tasks.map(\.id), ["a"])
        _ = try await coordinator.sync()
        let restarted = SyncCoordinator(storage: storage, remote: remote)
        let loaded = try await restarted.load()
        XCTAssertEqual(loaded.state.tasks.map(\.id), ["a"])
        await remote.setOnline(true)
        let synced = try await restarted.sync()
        XCTAssertFalse(synced.pending)
        let cloud = try await remote.fetch(account: "one", checkpoint: nil)
        XCTAssertEqual(cloud.snapshot?.state.tasks.map(\.id), ["a"])
    }

    func testFailedSaveDoesNotPublishSuccess() async throws {
        let storage = TestStorage(), remote = FakeRemote()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load()
        await storage.failing(true)
        do { _ = try await coordinator.apply([.addTask(WorkTask(id: "a", title: "A"))]); XCTFail() } catch {}
        let view = await coordinator.view()
        XCTAssertTrue(view.state.tasks.isEmpty)
    }

    func testLostUploadResponseIsSafeAfterRestart() async throws {
        let storage = TestStorage(), remote = FakeRemote()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load()
        _ = try await coordinator.apply([.addTask(WorkTask(id: "a", title: "A"))])
        await remote.dropResponse()
        _ = try await coordinator.sync()
        let restarted = SyncCoordinator(storage: storage, remote: remote)
        _ = try await restarted.load()
        let view = try await restarted.sync()
        XCTAssertEqual(view.state.tasks.map(\.id), ["a"])
        XCTAssertFalse(view.pending)
        XCTAssertTrue(view.conflicts.isEmpty)
    }

    func testAccountsDoNotUploadEachOthersLists() async throws {
        let storage = TestStorage(), remote = FakeRemote()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load()
        _ = try await coordinator.apply([.addTask(WorkTask(id: "a", title: "A"))])
        _ = try await coordinator.sync()
        await remote.setAccount(.available("two"))
        let other = try await coordinator.sync()
        XCTAssertTrue(other.state.tasks.isEmpty)
        _ = try await coordinator.apply([.addTask(WorkTask(id: "b", title: "B"))])
        _ = try await coordinator.sync()
        await remote.setAccount(.available("one"))
        let restored = try await coordinator.sync()
        XCTAssertEqual(restored.state.tasks.map(\.id), ["a"])
        await remote.setAccount(.signedOut)
        let local = try await coordinator.sync()
        XCTAssertTrue(local.state.tasks.isEmpty)
    }

    func testTwoDevicesMergeAdditionsAndResolveDeletion() async throws {
        let remote = FakeRemote()
        let a = SyncCoordinator(storage: TestStorage(), remote: remote)
        let bStorage = TestStorage()
        let b = SyncCoordinator(storage: bStorage, remote: remote)
        _ = try await a.load(); _ = try await b.load()
        _ = try await a.apply([.addTask(WorkTask(id: "a", title: "A"))])
        _ = try await a.sync(); _ = try await b.sync()
        _ = try await a.apply([.addTask(WorkTask(id: "b", title: "B"))])
        _ = try await b.apply([.addTask(WorkTask(id: "c", title: "C"))])
        _ = try await a.sync()
        let merged = try await b.sync()
        XCTAssertEqual(Set(merged.state.tasks.map(\.id)), ["a", "b", "c"])
        _ = try await a.sync()
        _ = try await a.apply([.deleteTask("a")])
        _ = try await b.apply([.renameTask("a", "Edited")])
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
        XCTAssertEqual(resolved.state.task("a")?.title, "Edited")
    }

    func testImportAndErasePropagate() async throws {
        let remote = FakeRemote()
        let a = SyncCoordinator(storage: TestStorage(), remote: remote)
        let b = SyncCoordinator(storage: TestStorage(), remote: remote)
        _ = try await a.load(); _ = try await b.load()
        _ = try await a.sync(); _ = try await b.sync()
        var imported = AppState()
        imported.tasks = [WorkTask(id: "new", title: "Imported")]; imported.actionOrder = ["new"]
        _ = try await a.replace(with: imported)
        _ = try await a.sync()
        let downloaded = try await b.sync()
        XCTAssertEqual(downloaded.state, imported)
        _ = try await b.apply([.eraseAll]); _ = try await b.sync()
        let erased = try await a.sync()
        XCTAssertTrue(erased.state.tasks.isEmpty)
    }
    func testStaleEditorCannotWriteIntoDifferentAccount() async throws {
        let remote = FakeRemote()
        let coordinator = SyncCoordinator(storage: TestStorage(), remote: remote)
        _ = try await coordinator.load()
        let first = try await coordinator.sync()
        await remote.setAccount(.available("two"))
        _ = try await coordinator.sync()
        do {
            _ = try await coordinator.apply([.addTask(WorkTask(id: "old", title: "Old account draft"))], expectedScope: first.scope)
            XCTFail("An old account's editor must not save into the new account")
        } catch {}
        let current = await coordinator.view()
        XCTAssertTrue(current.state.tasks.isEmpty)
    }

    func testUnknownAccountDoesNotSwitchOrLoseOfflineEdits() async throws {
        let remote = FakeRemote(), storage = TestStorage()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load(); _ = try await coordinator.sync()
        _ = try await coordinator.apply([.addTask(WorkTask(id: "a", title: "Offline"))])
        await remote.setAccount(.unavailable("Cannot determine account"))
        let unavailable = try await coordinator.sync()
        XCTAssertEqual(unavailable.state.tasks.map(\.id), ["a"])
        XCTAssertTrue(unavailable.pending)
        await remote.setAccount(.available("one"))
        let restored = try await coordinator.sync()
        XCTAssertEqual(restored.state.tasks.map(\.id), ["a"])
        XCTAssertFalse(restored.pending)
    }

    func testUnconfirmedUploadDoesNotResurrectTaskDeletedByAnotherDevice() async throws {
        let remote = FakeRemote(), storage = TestStorage()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load()
        _ = try await coordinator.apply([.addTask(WorkTask(id: "a", title: "A"))])
        await remote.dropResponse()
        _ = try await coordinator.sync()
        let uploaded = try await remote.fetch(account: "one", checkpoint: nil)
        _ = try await remote.publish(AppState(), account: "one", expecting: uploaded.snapshot?.revision, checkpoint: nil)
        let restart = SyncCoordinator(storage: storage, remote: remote)
        _ = try await restart.load()
        let uncertain = try await restart.sync()
        XCTAssertEqual(uncertain.conflicts.map(\.id), ["list.interrupted"])
        let cloud = try await remote.fetch(account: "one", checkpoint: nil)
        XCTAssertTrue(try XCTUnwrap(cloud.snapshot).state.tasks.isEmpty)
        _ = try await restart.resolve(["list.interrupted": .remote])
        let resolved = try await restart.sync()
        XCTAssertTrue(resolved.state.tasks.isEmpty)
    }

    func testConflictingVersionsStayFixedUntilResolution() async throws {
        let remote = FakeRemote()
        let a = SyncCoordinator(storage: TestStorage(), remote: remote)
        let b = SyncCoordinator(storage: TestStorage(), remote: remote)
        _ = try await a.load(); _ = try await b.load()
        _ = try await a.apply([.addTask(WorkTask(id: "a", title: "Original"))])
        _ = try await a.sync(); _ = try await b.sync()
        _ = try await a.apply([.renameTask("a", "First remote edit")])
        _ = try await b.apply([.renameTask("a", "Local edit")])
        _ = try await a.sync()
        let first = try await b.sync()
        _ = try await a.apply([.renameTask("a", "Second remote edit")]); _ = try await a.sync()
        let repeated = try await b.sync()
        XCTAssertEqual(repeated.conflicts, first.conflicts)
        _ = try await b.resolve(Dictionary(uniqueKeysWithValues: first.conflicts.map { ($0.id, MergeChoice.remote) }))
        let latest = try await b.sync()
        XCTAssertEqual(latest.state.task("a")?.title, "Second remote edit")
    }

    func testLocalAcknowledgementFailureRecoversWithoutDuplicateUpload() async throws {
        let remote = FakeRemote(), storage = TestStorage()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load()
        _ = try await coordinator.apply([.addTask(WorkTask(id: "a", title: "A"))])
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
        XCTAssertEqual(recovered.state.tasks.map(\.id), ["a"])
        XCTAssertEqual(final.snapshot?.revision, first.snapshot?.revision)
    }

    func testInvalidRemoteNeverReplacesSavedList() async throws {
        let remote = FakeRemote(), storage = TestStorage()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load()
        _ = try await coordinator.apply([.addTask(WorkTask(id: "a", title: "A"))])
        let before = try await coordinator.sync()
        var invalid = before.state
        invalid.tasks[0].prerequisiteIds = ["missing"]
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
        var state = AppState()
        state.tasks = [WorkTask(id: "contract", title: "Contract")]; state.actionOrder = ["contract"]
        let first = try await remote.publish(state, account: account, expecting: nil, checkpoint: nil)
        let revision = try XCTUnwrap(first.snapshot?.revision)
        do {
            _ = try await remote.publish(AppState(), account: account, expecting: nil, checkpoint: first.checkpoint)
            XCTFail("Create with a stale absent revision must fail")
        } catch RemoteSyncError.revisionConflict {}
        let retained = try await remote.fetch(account: account, checkpoint: first.checkpoint)
        XCTAssertEqual(retained.snapshot?.state, state)
        XCTAssertEqual(retained.snapshot?.revision, revision)
        let erased = try await remote.publish(AppState(), account: account, expecting: revision, checkpoint: retained.checkpoint)
        do {
            _ = try await remote.publish(state, account: account, expecting: revision, checkpoint: first.checkpoint)
            XCTFail("Stale update must not resurrect erased work")
        } catch RemoteSyncError.revisionConflict {}
        let final = try await remote.fetch(account: account, checkpoint: erased.checkpoint)
        XCTAssertEqual(final.snapshot?.state, AppState())
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
                    _ = try await coordinator.apply([.addTask(WorkTask(id: "\(index)", title: "Task \(index)"))])
                }
            }
            try await group.waitForAll()
        }
        let final = await coordinator.view()
        XCTAssertEqual(final.state.tasks.count, 20)
        XCTAssertEqual(Set(final.state.actionOrder).count, 20)
    }

    func testStaleSelectionCannotCompleteDifferentNextTask() async throws {
        let remote = FakeRemote()
        let coordinator = SyncCoordinator(storage: TestStorage(), remote: remote)
        _ = try await coordinator.load()
        _ = try await coordinator.apply([.addTask(WorkTask(id: "a", title: "A")),
                                         .addTask(WorkTask(id: "b", title: "B")), .urgent("a")])
        let displayed = try await coordinator.sync()
        let changed = try SelectionRules.transition(displayed.state, .urgent("b"))
        let fetched = try await remote.fetch(account: "one", checkpoint: nil)
        _ = try await remote.publish(changed, account: "one", expecting: fetched.snapshot?.revision, checkpoint: nil)
        _ = try await coordinator.sync()
        do {
            _ = try await coordinator.apply([.complete], expectedState: displayed.state)
            XCTFail("Done for A must not complete B")
        } catch {}
        let result = await coordinator.view()
        XCTAssertEqual(result.state.nextAction?.id, "b")
        XCTAssertNil(result.state.task("b")?.completedAt)
    }

    func testEditorOpeningSnapshotProtectsDownloadedRename() async throws {
        let remote = FakeRemote()
        let coordinator = SyncCoordinator(storage: TestStorage(), remote: remote)
        _ = try await coordinator.load()
        _ = try await coordinator.apply([.addTask(WorkTask(id: "a", title: "Original"))])
        let opening = try await coordinator.sync()
        let renamed = try SelectionRules.transition(opening.state, .renameTask("a", "Remote title"))
        let fetched = try await remote.fetch(account: "one", checkpoint: nil)
        _ = try await remote.publish(renamed, account: "one", expecting: fetched.snapshot?.revision, checkpoint: nil)
        _ = try await coordinator.sync()
        do {
            _ = try await coordinator.apply([.renameTask("a", "Original")], expectedState: opening.state)
            XCTFail("Stale editor must not restore the old title")
        } catch {}
        let result = await coordinator.view()
        XCTAssertEqual(result.state.task("a")?.title, "Remote title")
    }

}
