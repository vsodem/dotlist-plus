import DotListPlusCore
import DotListPlusApplication
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// The disk format is private to this adapter; callers exchange validated transactions.
public actor JSONLocalStorage: LocalStorage {
    private let directory: URL
    private var url: URL { directory.appendingPathComponent(ProductIdentity.localFile) }

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(ProductIdentity.localDirectory, isDirectory: true)
    }

    public func load() async throws -> LocalStoreState {
        if let data = try readIfPresent(url) {
            let lists = try FormatEnvelope.decode(LocalStoreState.self, from: data, format: .localStore)
            try lists.validate()
            return lists
        }
        return LocalStoreState()
    }

    public func save(_ lists: LocalStoreState, preserveRecovery: Bool) async throws {
        try lists.validate()
        try Task.checkCancellation()
        // Even a fresh adapter must refuse to overwrite incompatible existing bytes.
        if let existing = try readIfPresent(url) {
            let saved = try FormatEnvelope.decode(LocalStoreState.self, from: existing, format: .localStore)
            try saved.validate()
        }
        let data = try FormatEnvelope.encode(lists, format: .localStore)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if preserveRecovery, let existing = try readIfPresent(url) {
            try writeAtomically(existing, to: directory.appendingPathComponent("dot-list-plus-recovery-\(UUID().uuidString).json"))
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
