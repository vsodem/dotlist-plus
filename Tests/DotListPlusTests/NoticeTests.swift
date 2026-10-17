import XCTest
import DotListPlusCore
import DotListPlusApplication
import DotListPlusStorage

final class NoticeTests: XCTestCase {
    func testDismissalSurvivesEditSyncAndDiskRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = JSONLocalStorage(directory: directory), remote = FakeRemote()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load()
        _ = try await coordinator.sync()
        let displayed = try await coordinator.replace(with: ListState(), notice: "Imported")
        let before = try await storage.load()
        let fetches = await remote.fetchCount, uploads = await remote.publishCount
        let dismissed = try await coordinator.dismissNotice(expectedScope: displayed.scope, expectedGeneration: displayed.generation)
        XCTAssertNil(dismissed.notice)
        XCTAssertEqual(dismissed.generation, displayed.generation + 1)
        var expected = before
        expected.current.notice = nil
        let saved = try await storage.load()
        XCTAssertEqual(saved, expected)
        let laterFetches = await remote.fetchCount, laterUploads = await remote.publishCount
        XCTAssertEqual(laterFetches, fetches)
        XCTAssertEqual(laterUploads, uploads)
        let edited = try await coordinator.apply([.addWorkItem(WorkItem(id: "a", title: "A"))])
        XCTAssertNil(edited.notice)
        let synced = try await coordinator.sync()
        XCTAssertNil(synced.notice)
        XCTAssertFalse(synced.pending)
        let restarted = SyncCoordinator(storage: JSONLocalStorage(directory: directory), remote: remote)
        let restored = try await restarted.load()
        XCTAssertNil(restored.notice)
        XCTAssertEqual(restored.state, edited.state)
    }

    func testDismissalPreservesAllSyncMetadataAndOtherPartitions() async throws {
        let storage = TestStorage(), remote = FakeRemote()
        var lists = LocalStoreState()
        lists.activeAccount = "fake:one"
        lists.adoptedLocalList = true
        var current = AccountListState()
        current.notice = "Review changed"
        current.pending = true
        current.baseline = RemoteSnapshot(state: ListState(), revision: "base")
        current.checkpoint = ProviderCheckpoint(provider: "fake", data: Data([1, 2]))
        current.outgoingAttempt = OutgoingAttempt(state: ListState(), expectedRevision: "base")
        current.conflict = PendingConflict(base: ListState(), local: ListState(),
                                          remote: RemoteSnapshot(state: ListState(), revision: "remote"))
        lists.accounts["fake:one"] = current
        lists.accounts["fake:two"] = current
        lists.local.notice = "Local notice"
        try await storage.save(lists, preserveRecovery: false)
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        let displayed = try await coordinator.load()
        let result = try await coordinator.dismissNotice(expectedScope: displayed.scope, expectedGeneration: displayed.generation)
        lists.current.notice = nil
        let saved = try await storage.load()
        XCTAssertEqual(saved, lists)
        XCTAssertEqual(result.pending, displayed.pending)
        XCTAssertEqual(result.conflicts, displayed.conflicts)
        XCTAssertEqual(result.status, displayed.status)
    }

    func testFailedDismissalRetainsSavedAndVisibleNotice() async throws {
        let storage = TestStorage()
        let coordinator = SyncCoordinator(storage: storage, remote: FakeRemote())
        _ = try await coordinator.load()
        let displayed = try await coordinator.replace(with: ListState(), notice: "Keep me")
        let before = try await storage.load()
        await storage.failing(true)
        do {
            _ = try await coordinator.dismissNotice(expectedScope: displayed.scope, expectedGeneration: displayed.generation)
            XCTFail("Failed save must not dismiss")
        } catch { XCTAssertEqual(error as? RuleError, RuleError("Disk full")) }
        let visible = await coordinator.snapshot(), saved = try await storage.load()
        XCTAssertEqual(visible.notice, displayed.notice)
        XCTAssertEqual(visible.generation, displayed.generation)
        XCTAssertEqual(saved, before)
    }

    func testOldGenerationCannotDismissNewNoticeEvenWithSameText() async throws {
        for text in ["Same text", "Different text"] {
            let storage = TestStorage()
            let coordinator = SyncCoordinator(storage: storage, remote: FakeRemote())
            _ = try await coordinator.load()
            let old = try await coordinator.replace(with: ListState(), notice: "Same text")
            let latest = try await coordinator.replace(with: ListState(), notice: text)
            let before = try await storage.load()
            await storage.failing(true) // A stale dismissal must not even attempt a save.
            let result = try await coordinator.dismissNotice(expectedScope: old.scope, expectedGeneration: old.generation)
            XCTAssertEqual(result.notice, text)
            XCTAssertEqual(result.generation, latest.generation)
            let saved = try await storage.load()
            XCTAssertEqual(saved, before)
        }
    }

    func testInterveningEditRequiresAnotherClick() async throws {
        let coordinator = SyncCoordinator(storage: TestStorage(), remote: FakeRemote())
        _ = try await coordinator.load()
        let old = try await coordinator.replace(with: ListState(), notice: "Notice")
        let edited = try await coordinator.apply([.addWorkItem(WorkItem(id: "a", title: "A"))])
        let stale = try await coordinator.dismissNotice(expectedScope: old.scope, expectedGeneration: old.generation)
        XCTAssertEqual(stale.notice, "Notice")
        XCTAssertEqual(stale.state, edited.state)
        XCTAssertEqual(stale.generation, edited.generation)
        let dismissed = try await coordinator.dismissNotice(expectedScope: stale.scope, expectedGeneration: stale.generation)
        XCTAssertNil(dismissed.notice)
        XCTAssertEqual(dismissed.state, edited.state)
    }

    func testOldAccountCannotDismissCurrentAccountNotice() async throws {
        let storage = TestStorage(), remote = FakeRemote()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        _ = try await coordinator.load(); _ = try await coordinator.sync()
        let first = try await coordinator.replace(with: ListState(), notice: "Same text")
        await remote.setAccount(.available("two"))
        _ = try await coordinator.sync()
        let second = try await coordinator.replace(with: ListState(), notice: "Same text")
        let before = try await storage.load()
        do {
            _ = try await coordinator.dismissNotice(expectedScope: first.scope, expectedGeneration: first.generation)
            XCTFail("An old click must not dismiss another account's notice")
        } catch {
            XCTAssertEqual(error as? RuleError, RuleError("The account changed while you were editing. Open the list again before saving."))
        }
        let saved = try await storage.load(), visible = await coordinator.snapshot()
        XCTAssertEqual(saved, before)
        XCTAssertEqual(visible.scope, second.scope)
        XCTAssertEqual(visible.notice, second.notice)
    }

    func testCancelledDismissalDoesNotCommit() async throws {
        let storage = TestStorage()
        let coordinator = SyncCoordinator(storage: storage, remote: FakeRemote())
        _ = try await coordinator.load()
        let displayed = try await coordinator.replace(with: ListState(), notice: "Keep me")
        let before = try await storage.load()
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await coordinator.dismissNotice(expectedScope: displayed.scope, expectedGeneration: displayed.generation)
        }
        do { _ = try await operation.value; XCTFail("Cancelled dismissal must not save") }
        catch is CancellationError {} catch { XCTFail("Wrong error: \(error)") }
        let saved = try await storage.load(), visible = await coordinator.snapshot()
        XCTAssertEqual(saved, before)
        XCTAssertEqual(visible.notice, displayed.notice)
        XCTAssertEqual(visible.generation, displayed.generation)
    }

    func testDismissalWithoutNoticeDoesNotSave() async throws {
        let storage = TestStorage()
        let coordinator = SyncCoordinator(storage: storage, remote: FakeRemote())
        let displayed = try await coordinator.load()
        await storage.failing(true)
        let result = try await coordinator.dismissNotice(expectedScope: displayed.scope, expectedGeneration: displayed.generation)
        XCTAssertNil(result.notice)
        XCTAssertEqual(result.generation, displayed.generation)
    }

    func testDismissalRequiresLoadedStore() async throws {
        let coordinator = SyncCoordinator(storage: TestStorage(), remote: FakeRemote())
        do {
            _ = try await coordinator.dismissNotice(expectedScope: "local", expectedGeneration: 0)
            XCTFail("Load must succeed before dismissal")
        } catch { XCTAssertEqual(error as? RuleError, RuleError("Open or recover the saved list before making changes.")) }
    }
}

extension NoticeTests {
    func testDismissalWaitsForInterveningSaveAndKeepsNewGeneration() async throws {
        let storage = SuspendedNoticeStorage()
        let coordinator = SyncCoordinator(storage: storage, remote: FakeRemote())
        let displayed = try await coordinator.load()
        let edit = Task { try await coordinator.apply([.addWorkItem(WorkItem(id: "a", title: "A"))]) }
        await storage.waitForSave()
        let dismissal = Task {
            try await coordinator.dismissNotice(expectedScope: displayed.scope, expectedGeneration: displayed.generation)
        }
        await storage.finishSave()
        let edited = try await edit.value, result = try await dismissal.value
        XCTAssertEqual(result.generation, edited.generation)
        XCTAssertEqual(result.state, edited.state)
        XCTAssertEqual(result.notice, "Notice")
        let saved = try await storage.load()
        XCTAssertEqual(saved.current.state, edited.state)
        XCTAssertEqual(saved.current.notice, "Notice")
    }

    func testCancellationAfterDismissalSaveStillExposesDurableSnapshot() async throws {
        let storage = SuspendedNoticeStorage(cancelAfterSave: true)
        let coordinator = SyncCoordinator(storage: storage, remote: FakeRemote())
        let displayed = try await coordinator.load()
        let dismissal = Task {
            try await coordinator.dismissNotice(expectedScope: displayed.scope, expectedGeneration: displayed.generation)
        }
        await storage.waitForSave()
        let whileSaving = await coordinator.snapshot(), savedBefore = try await storage.load()
        XCTAssertEqual(whileSaving.notice, "Notice")
        XCTAssertEqual(savedBefore.current.notice, "Notice")
        await storage.finishSave()
        let result = try await dismissal.value
        let saved = try await storage.load(), visible = await coordinator.snapshot()
        XCTAssertNil(result.notice)
        XCTAssertNil(saved.current.notice)
        XCTAssertNil(visible.notice)
        XCTAssertEqual(result.generation, displayed.generation + 1)
    }
}

private actor SuspendedNoticeStorage: LocalStorage {
    private var lists: LocalStoreState
    private var saveStarted = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var saveWaiter: CheckedContinuation<Void, Never>?
    private let cancelAfterSave: Bool
    init(cancelAfterSave: Bool = false) {
        self.cancelAfterSave = cancelAfterSave
        lists = LocalStoreState()
        lists.local.notice = "Notice"
    }
    func load() async throws -> LocalStoreState { lists }
    func save(_ lists: LocalStoreState, preserveRecovery: Bool) async throws {
        try lists.validate()
        if !saveStarted {
            saveStarted = true
            startWaiter?.resume(); startWaiter = nil
            await withCheckedContinuation { saveWaiter = $0 }
        }
        self.lists = lists
        if cancelAfterSave { withUnsafeCurrentTask { $0?.cancel() } }
    }
    func waitForSave() async {
        if !saveStarted { await withCheckedContinuation { startWaiter = $0 } }
    }
    func finishSave() { saveWaiter?.resume(); saveWaiter = nil }
}
