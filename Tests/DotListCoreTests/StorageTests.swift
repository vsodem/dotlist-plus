import Foundation
import XCTest
import DotListCore
import DotListStorage

actor InMemoryStorage: LocalStorage {
    private var lists = StoredLists()
    private(set) var recovery: [StoredLists] = []

    func load() async throws -> StoredLists { lists }
    func save(_ lists: StoredLists, preserveRecovery: Bool) async throws {
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

    func state() throws -> AppState {
        var state = AppState()
        state = try SelectionRules.transition(state, .addTask(WorkTask(id: "A", title: "First")))
        state = try SelectionRules.transition(state, .addTask(WorkTask(id: "B", title: "Second")))
        return try SelectionRules.transition(state, .beginReview)
    }

    func checkContract(_ storage: any LocalStorage) async throws {
        let empty = try await storage.load()
        XCTAssertEqual(empty, StoredLists())
        var lists = StoredLists()
        lists.local.state = try state()
        lists.activeAccount = "account-a"
        var account = AccountList(state: try state())
        account.baseline = RemoteSnapshot(state: account.state, revision: "rev-1")
        account.pending = true
        account.outgoingAttempt = OutgoingAttempt(state: account.state, expectedRevision: "rev-1")
        account.checkpoint = ProviderCheckpoint(provider: "test", data: Data([1, 2]))
        account.conflict = PendingConflict(base: account.state, local: account.state,
                                           remote: RemoteSnapshot(state: AppState(), revision: "rev-2"))
        account.notice = "Review needed"
        lists.accounts["account-a"] = account
        lists.accounts["account-b"] = AccountList()
        try await storage.save(lists, preserveRecovery: false)
        let restored = try await storage.load()
        XCTAssertEqual(restored, lists)
        var invalid = lists
        invalid.accounts["account-b"]?.state.actionOrder = ["missing"]
        do {
            try await storage.save(invalid, preserveRecovery: false)
            XCTFail("Invalid inactive account should reject the whole transaction")
        } catch {}
        let afterFailure = try await storage.load()
        XCTAssertEqual(afterFailure, lists)
        try await storage.save(StoredLists(), preserveRecovery: true)
        let erased = try await storage.load()
        XCTAssertEqual(erased, StoredLists())
    }

    func testMemoryStorageContract() async throws { try await checkContract(InMemoryStorage()) }

    func testJSONStorageContractAndRecovery() async throws {
        let directory = try directory()
        try await checkContract(JSONLocalStorage(directory: directory))
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("backup-") }
        XCTAssertEqual(backups.count, 1)
        let recovered = try JSONDecoder().decode(StoredLists.self, from: Data(contentsOf: XCTUnwrap(backups.first)))
        XCTAssertEqual(recovered.activeAccount, "account-a")
        XCTAssertEqual(recovered.current.state, try state())
        XCTAssertNotNil(recovered.current.conflict)
    }

    func testMigrationPreservesOriginalAndResumesReviewOnRestart() async throws {
        let directory = try directory()
        let original = try state()
        let bytes = try BackupCodec.encode(original)
        let legacy = directory.appendingPathComponent("state-v2.json")
        try bytes.write(to: legacy)
        let loaded = try await JSONLocalStorage(directory: directory).load()
        XCTAssertEqual(loaded.local.state, original)
        XCTAssertEqual(try Data(contentsOf: legacy), bytes)
        let envelope = directory.appendingPathComponent("sync-state-v1.json")
        XCTAssertEqual(try JSONDecoder().decode(StoredLists.self, from: Data(contentsOf: envelope)), loaded)
        try Data("corrupt old file".utf8).write(to: legacy)
        let restarted = try await JSONLocalStorage(directory: directory).load()
        XCTAssertEqual(restarted, loaded)
    }

    func testBrowserMigrationPreservesIDsAndRecoveryNotice() async throws {
        let directory = try directory()
        let bytes = Data(#"{"tasks":[{"id":"old","text":"Task","doneAt":null}]}"#.utf8)
        try bytes.write(to: directory.appendingPathComponent("state-v2.json"))
        let loaded = try await JSONLocalStorage(directory: directory).load()
        XCTAssertEqual(loaded.local.state.tasks.map(\.id), ["old"])
        XCTAssertNotNil(loaded.local.notice)
    }

    func testUnreadableEnvelopeNeverFallsBackToLegacyOrEmpty() async throws {
        let directory = try directory()
        try BackupCodec.encode(try state()).write(to: directory.appendingPathComponent("state-v2.json"))
        let envelope = directory.appendingPathComponent("sync-state-v1.json")
        let corrupt = Data("corrupt".utf8)
        try corrupt.write(to: envelope)
        do {
            _ = try await JSONLocalStorage(directory: directory).load()
            XCTFail("A corrupt envelope must stop loading")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: envelope), corrupt)
        try await JSONLocalStorage(directory: directory).save(StoredLists(), preserveRecovery: true)
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("backup-") }
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), corrupt)
    }

    func testUnreadableExistingFileDoesNotBecomeAnEmptyList() async throws {
        let directory = try directory()
        let envelope = directory.appendingPathComponent("sync-state-v1.json")
        try await JSONLocalStorage(directory: directory).save(StoredLists(), preserveRecovery: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: envelope.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: envelope.path) }
        do {
            _ = try await JSONLocalStorage(directory: directory).load()
            XCTFail("Permission failure must stop loading")
        } catch {}
    }

    func testInvalidStoredAccountFailsLoadWithoutChangingBytes() async throws {
        let directory = try directory()
        let envelope = directory.appendingPathComponent("sync-state-v1.json")
        var invalid = StoredLists()
        var account = AccountList()
        account.state.actionOrder = ["missing"]
        invalid.accounts["inactive"] = account
        let bytes = try JSONEncoder().encode(invalid)
        try bytes.write(to: envelope)
        do {
            _ = try await JSONLocalStorage(directory: directory).load()
            XCTFail("Stored inactive accounts must be validated")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: envelope), bytes)
    }

    func testCorruptLegacyFileIsPreservedAndFailsLoad() async throws {
        let directory = try directory()
        let legacy = directory.appendingPathComponent("state-v2.json")
        let corrupt = Data("corrupt".utf8)
        try corrupt.write(to: legacy)
        do {
            _ = try await JSONLocalStorage(directory: directory).load()
            XCTFail("A corrupt legacy file must stop loading")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: legacy), corrupt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("sync-state-v1.json").path))
    }

    func testFailedWritePreservesExistingBytes() async throws {
        let directory = try directory()
        let storage = JSONLocalStorage(directory: directory)
        var lists = StoredLists()
        lists.local.state = try state()
        try await storage.save(lists, preserveRecovery: false)
        let envelope = directory.appendingPathComponent("sync-state-v1.json")
        let bytes = try Data(contentsOf: envelope)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        for preserveRecovery in [false, true] {
            do {
                try await storage.save(StoredLists(), preserveRecovery: preserveRecovery)
                XCTFail("Read-only directory must reject the replacement")
            } catch {}
            XCTAssertEqual(try Data(contentsOf: envelope), bytes)
        }
    }

    func testMigrationWriteFailureDoesNotReturnUnsavedState() async throws {
        let directory = try directory()
        let legacy = directory.appendingPathComponent("state-v2.json")
        let bytes = try BackupCodec.encode(try state())
        try bytes.write(to: legacy)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        do {
            _ = try await JSONLocalStorage(directory: directory).load()
            XCTFail("Migration must persist before returning")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: legacy), bytes)
    }
}
