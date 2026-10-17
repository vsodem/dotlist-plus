import Foundation
import CloudKit
import DotListPlusCore
import DotListPlusApplication

/// Provider encoding stays internal. Both fetch and publication use this validation.
enum CloudSnapshotCodec {
    static func encode(_ state: ListState) throws -> Data {
        try LocalStoreState.validate(state)
        return try FormatEnvelope.encode(state, format: .cloudSnapshot)
    }
    static func decode(_ data: Data) throws -> ListState {
        let state = try FormatEnvelope.decode(ListState.self, from: data, format: .cloudSnapshot)
        try LocalStoreState.validate(state)
        return state
    }
    static func decodeRecord(_ record: CKRecord, account: String, recordID: CKRecord.ID) throws -> ListState {
        guard record.recordType == "ListSnapshot", record.recordID == recordID,
              record["account"] as? String == account, record["formatVersion"] as? Int == 1,
              let asset = record["listJSON"] as? CKAsset, let url = asset.fileURL else {
            throw RemoteSyncError.unavailable("The iCloud list has an unsupported or incomplete format. Your local list was kept.")
        }
        return try decode(Data(contentsOf: url))
    }

    /// Complete preflight before writing an asset or modifying the record.
    static func preparePublication(_ state: ListState, existing: CKRecord?, expectedTag: String?,
                                   account: String, recordID: CKRecord.ID, assetURL: URL) throws -> CKRecord {
        guard existing?.recordChangeTag == expectedTag else { throw RemoteSyncError.revisionConflict }
        if let existing { _ = try decodeRecord(existing, account: account, recordID: recordID) }
        let data = try encode(state)
        try data.write(to: assetURL, options: .atomic)
        let record = existing ?? CKRecord(recordType: "ListSnapshot", recordID: recordID)
        record["listJSON"] = CKAsset(fileURL: assetURL)
        record["formatVersion"] = 1 as CKRecordValue
        record["account"] = account as CKRecordValue
        return record
    }
}
