import Foundation
#if canImport(DotListCore)
import DotListCore
#endif
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The disk format is private to this adapter; callers exchange validated transactions.
public actor JSONLocalStorage: LocalStorage {
    private let directory: URL
    private var url: URL { directory.appendingPathComponent("sync-state-v1.json") }
    private var legacyURL: URL { directory.appendingPathComponent("state-v2.json") }

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DotList", isDirectory: true)
    }

    public func load() async throws -> StoredLists {
        if let data = try readIfPresent(url) {
            let lists = try JSONDecoder().decode(StoredLists.self, from: data)
            try lists.validate()
            return lists
        }
        guard let data = try readIfPresent(legacyURL) else { return StoredLists() }
        let imported = try BackupCodec.decode(data)
        var lists = StoredLists()
        lists.local.state = imported.state
        lists.local.notice = imported.notice
        try await save(lists, preserveRecovery: false)
        return lists
    }

    public func save(_ lists: StoredLists, preserveRecovery: Bool) async throws {
        try lists.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(lists)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if preserveRecovery, let existing = try readIfPresent(url) {
            try writeAtomically(existing, to: directory.appendingPathComponent("backup-\(UUID().uuidString).json"))
        }
        try writeAtomically(data, to: url)
    }

    private func readIfPresent(_ url: URL) throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
    }

    /// Flush a sibling temporary file before atomic rename. A failure before rename
    /// leaves the last committed transaction intact.
    private func writeAtomically(_ data: Data, to destination: URL) throws {
        let temporary = directory.appendingPathComponent(".write-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        try handle.synchronize()
        if rename(temporary.path, destination.path) != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}
