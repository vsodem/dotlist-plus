import Foundation
import XCTest
import DotListPlusCore
import DotListPlusApplication
import DotListPlusStorage

actor InMemoryStorage: LocalStorage {
    private var lists = LocalStoreState()
    private(set) var recovery: [LocalStoreState] = []

    func load() async throws -> LocalStoreState { lists }
    func save(_ lists: LocalStoreState, preserveRecovery: Bool) async throws {
        try lists.validate()
        if preserveRecovery { recovery.append(self.lists) }
        self.lists = lists
    }
}

final class StorageTests: XCTestCase {
    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    func state() throws -> ListState {
        var state = ListState()
        state = try ListRules.transition(state, .addWorkItem(WorkItem(id: "A", title: "First")))
        state = try ListRules.transition(state, .addWorkItem(WorkItem(id: "B", title: "Second")))
        return try ListRules.transition(state, .beginReview)
    }

    func checkContract(_ storage: any LocalStorage) async throws {
        let empty = try await storage.load()
        XCTAssertEqual(empty, LocalStoreState())
        var lists = LocalStoreState()
        lists.local.state = try state()
        lists.activeAccount = "account-a"
        var account = AccountListState(state: try state())
        account.baseline = RemoteSnapshot(state: account.state, revision: "rev-1")
        account.pending = true
        account.outgoingAttempt = OutgoingAttempt(state: account.state, expectedRevision: "rev-1")
        account.checkpoint = ProviderCheckpoint(provider: "test", data: Data([1, 2]))
        account.conflict = PendingConflict(base: account.state, local: account.state,
                                           remote: RemoteSnapshot(state: ListState(), revision: "rev-2"))
        account.notice = "Review needed"
        lists.accounts["account-a"] = account
        lists.accounts["account-b"] = AccountListState()
        try await storage.save(lists, preserveRecovery: false)
        let restored = try await storage.load()
        XCTAssertEqual(restored, lists)
        var invalid = lists
        invalid.accounts["account-b"]?.state.actionOrder = ["missing"]
        do {
            try await storage.save(invalid, preserveRecovery: false)
            XCTFail("Invalid inactive account should reject the whole transaction")
        } catch { XCTAssertEqual(error as? RuleError, RuleError("The action order must contain every unfinished action exactly once.")) }
        let afterFailure = try await storage.load()
        XCTAssertEqual(afterFailure, lists)
        try await storage.save(LocalStoreState(), preserveRecovery: true)
        let erased = try await storage.load()
        XCTAssertEqual(erased, LocalStoreState())
    }

    func testMemoryStorageContract() async throws { try await checkContract(InMemoryStorage()) }

    func testJSONStorageContractAndRecovery() async throws {
        let directory = try directory()
        try await checkContract(JSONLocalStorage(directory: directory))
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("dot-list-plus-recovery-") }
        XCTAssertEqual(backups.count, 1)
        let recovered = try FormatEnvelope.decode(LocalStoreState.self, from: Data(contentsOf: XCTUnwrap(backups.first)), format: .localStore)
        XCTAssertEqual(recovered.activeAccount, "account-a")
        XCTAssertEqual(recovered.current.state, try state())
        XCTAssertNotNil(recovered.current.conflict)
    }

    func testOldFilesRemainUntouchedAndNewStoreRestarts() async throws {
        let directory = try directory()
        let oldFiles = ["state-v2.json", "sync-state-v1.json", "dotlist-v1.json"]
        let bytes = Data("old format, deliberately unreadable".utf8)
        for name in oldFiles { try bytes.write(to: directory.appendingPathComponent(name)) }
        let storage = JSONLocalStorage(directory: directory)
        let empty = try await storage.load()
        XCTAssertEqual(empty, LocalStoreState())
        var saved = LocalStoreState()
        saved.local.state = try state()
        try await storage.save(saved, preserveRecovery: false)
        let restarted = try await JSONLocalStorage(directory: directory).load()
        XCTAssertEqual(restarted, saved)
        for name in oldFiles { XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(name)), bytes) }
    }

    func testIncompatibleStoreBlocksLoadAndEveryOrdinarySave() async throws {
        let directory = try directory()
        let url = directory.appendingPathComponent(ProductIdentity.localFile)
        let candidates: [(Data, (Error) -> Void)] = [
            (Data("corrupt".utf8), { error in
                guard case DecodingError.dataCorrupted = error else { return XCTFail("Wrong error: \(error)") }
            }),
            (try BackupCodec.encode(ListState()), { error in
                XCTAssertEqual(error as? RuleError, RuleError("This file is not a supported Dot List Plus localStore version. The original data was kept."))
            }),
            (try JSONEncoder().encode(LocalStoreState()), { error in
                guard case DecodingError.keyNotFound(let key, _) = error else { return XCTFail("Wrong error: \(error)") }
                XCTAssertEqual(key.stringValue, "productID")
            })
        ]
        for (bytes, checkError) in candidates {
            try bytes.write(to: url)
            let storage = JSONLocalStorage(directory: directory)
            do { _ = try await storage.load(); XCTFail("Incompatible store must block load") } catch { checkError(error) }
            for recovery in [false, true] {
                do { try await storage.save(LocalStoreState(), preserveRecovery: recovery); XCTFail("Must preserve incompatible store") } catch { checkError(error) }
                XCTAssertEqual(try Data(contentsOf: url), bytes)
            }
        }
    }

    func testUnreadableExistingFileDoesNotBecomeAnEmptyList() async throws {
        let directory = try directory()
        let envelope = directory.appendingPathComponent(ProductIdentity.localFile)
        try await JSONLocalStorage(directory: directory).save(LocalStoreState(), preserveRecovery: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: envelope.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: envelope.path) }
        do {
            _ = try await JSONLocalStorage(directory: directory).load()
            XCTFail("Permission failure must stop loading")
        } catch { XCTAssertEqual((error as? CocoaError)?.code, .fileReadNoPermission) }
    }

    func testInvalidStoredAccountFailsLoadWithoutChangingBytes() async throws {
        let directory = try directory()
        let envelope = directory.appendingPathComponent(ProductIdentity.localFile)
        var invalid = LocalStoreState()
        var account = AccountListState()
        account.state.actionOrder = ["missing"]
        invalid.accounts["inactive"] = account
        let bytes = try FormatEnvelope.encode(invalid, format: .localStore)
        try bytes.write(to: envelope)
        do {
            _ = try await JSONLocalStorage(directory: directory).load()
            XCTFail("Stored inactive accounts must be validated")
        } catch { XCTAssertEqual(error as? RuleError, RuleError("The action order must contain every unfinished action exactly once.")) }
        XCTAssertEqual(try Data(contentsOf: envelope), bytes)
    }

    func testFailedWritePreservesExistingBytes() async throws {
        let directory = try directory()
        let storage = JSONLocalStorage(directory: directory)
        var lists = LocalStoreState()
        lists.local.state = try state()
        try await storage.save(lists, preserveRecovery: false)
        let envelope = directory.appendingPathComponent(ProductIdentity.localFile)
        let bytes = try Data(contentsOf: envelope)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        for preserveRecovery in [false, true] {
            do {
                try await storage.save(LocalStoreState(), preserveRecovery: preserveRecovery)
                XCTFail("Read-only directory must reject the replacement")
            } catch { XCTAssertEqual((error as? CocoaError)?.code, .fileWriteNoPermission) }
            XCTAssertEqual(try Data(contentsOf: envelope), bytes)
        }
    }

}
