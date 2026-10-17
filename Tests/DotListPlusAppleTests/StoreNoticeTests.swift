import XCTest
import DotListPlusCore
import DotListPlusApplication
@testable import DotListPlusUI

final class StoreNoticeTests: XCTestCase {
    @MainActor
    func testFailedSaveRetainsBannerAndDisplaysError() async throws {
        let storage = NoticeUIStorage(), remote = NoticeUIRemote()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        let store = DotListPlusStore(coordinator: coordinator, syncServiceName: "Test")
        await remote.waitForObservation()
        XCTAssertEqual(store.notice, "Notice")
        await storage.setFailure(true)
        let dismissal = try XCTUnwrap(store.dismissNotice())
        XCTAssertTrue(store.saving)
        XCTAssertEqual(store.notice, "Notice")
        await dismissal.value
        XCTAssertFalse(store.saving)
        XCTAssertEqual(store.notice, "Notice")
        XCTAssertEqual(store.error, "Notice not dismissed. Disk full")
        let saved = try await storage.load()
        XCTAssertEqual(saved.local.notice, "Notice")
        await storage.setFailure(false)
        await store.dismissNotice()?.value
        XCTAssertNil(store.notice)
        XCTAssertNil(store.error)
        let after = try await storage.load(), accountCalls = await remote.accountCalls
        XCTAssertNil(after.local.notice)
        XCTAssertEqual(accountCalls, 1, "Dismissal must not initiate sync, including account lookup")
    }

    @MainActor
    func testClickUsesDisplayedGenerationAndShowsNewerSnapshot() async throws {
        let storage = NoticeUIStorage(), remote = NoticeUIRemote()
        let coordinator = SyncCoordinator(storage: storage, remote: remote)
        let store = DotListPlusStore(coordinator: coordinator, syncServiceName: "Test")
        await remote.waitForObservation()
        // The coordinator has a new notice, but the screen still displays the old generation.
        _ = try await coordinator.replace(with: ListState(), notice: "Notice")
        await store.dismissNotice()?.value
        XCTAssertEqual(store.notice, "Notice")
        let retained = try await storage.load()
        XCTAssertEqual(retained.local.notice, "Notice")
        await store.dismissNotice()?.value
        XCTAssertNil(store.notice)
        let dismissed = try await storage.load()
        XCTAssertNil(dismissed.local.notice)
    }
}

private actor NoticeUIStorage: LocalStorage {
    private var lists: LocalStoreState
    private var failing = false
    init() {
        lists = LocalStoreState()
        lists.local.notice = "Notice"
    }
    func setFailure(_ value: Bool) { failing = value }
    func load() async throws -> LocalStoreState { lists }
    func save(_ lists: LocalStoreState, preserveRecovery: Bool) async throws {
        if failing { throw RuleError("Disk full") }
        try lists.validate()
        self.lists = lists
    }
}

private actor NoticeUIRemote: RemoteSync {
    nonisolated let providerID = "notice-test"
    private var observing = false
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var accountCalls = 0
    func account() async -> RemoteAccount { accountCalls += 1; return .signedOut }
    func fetch(account: String, checkpoint: ProviderCheckpoint?) async throws -> RemoteExchange {
        XCTFail("Signed-out store must not fetch")
        throw RemoteSyncError.accountChanged
    }
    func publish(_ state: ListState, account: String, expecting revision: String?,
                 checkpoint: ProviderCheckpoint?) async throws -> RemoteExchange {
        XCTFail("Signed-out store must not publish")
        throw RemoteSyncError.accountChanged
    }
    func requests() async -> AsyncStream<Void> {
        observing = true
        waiter?.resume(); waiter = nil
        return AsyncStream { $0.finish() }
    }
    func waitForObservation() async {
        if !observing { await withCheckedContinuation { waiter = $0 } }
    }
}
