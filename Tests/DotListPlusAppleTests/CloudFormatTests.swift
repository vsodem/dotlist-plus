import XCTest
import DotListPlusCore
import DotListPlusApplication
@testable import DotListPlusCloudKit

final class CloudFormatTests: XCTestCase {
    func testCloudPayloadRoundTripAndRejectsPortableAndLegacyData() throws {
        let state = try ListRules.transition(ListState(), .addWorkItem(WorkItem(id: "a", title: "A")))
        XCTAssertEqual(try CloudSnapshotCodec.decode(CloudSnapshotCodec.encode(state)), state)
        XCTAssertThrowsError(try CloudSnapshotCodec.decode(BackupCodec.encode(state))) {
            XCTAssertEqual($0 as? RuleError, RuleError("This file is not a supported Dot List Plus cloudSnapshot version. The original data was kept."))
        }
        XCTAssertThrowsError(try CloudSnapshotCodec.decode(JSONEncoder().encode(state))) {
            guard case DecodingError.keyNotFound(let key, _) = $0 else { return XCTFail("Wrong error: \($0)") }
            XCTAssertEqual(key.stringValue, "productID")
        }
        XCTAssertThrowsError(try CloudSnapshotCodec.decode(FormatEnvelope.encode(LocalStoreState(), format: .localStore))) {
            XCTAssertEqual($0 as? RuleError, RuleError("This file is not a supported Dot List Plus cloudSnapshot version. The original data was kept."))
        }
        var invalid = state
        invalid.workItems[0].prerequisiteIDs = ["missing"]
        XCTAssertThrowsError(try CloudSnapshotCodec.decode(FormatEnvelope.encode(invalid, format: .cloudSnapshot))) {
            XCTAssertEqual($0 as? RuleError, RuleError("‘A’ has a missing prerequisite or a prerequisite that is not an action."))
        }
        XCTAssertThrowsError(try CloudSnapshotCodec.encode(invalid)) {
            XCTAssertEqual($0 as? RuleError, RuleError("‘A’ has a missing prerequisite or a prerequisite that is not an action."))
        }
    }
}

import CloudKit

extension CloudFormatTests {
    func testIncompatibleExistingCloudRecordNeverPreparesAnUpload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("existing.json")
        let output = directory.appendingPathComponent("upload.json")
        let id = CKRecord.ID(recordName: "complete-list", zoneID: CKRecordZone.ID(zoneName: ProductIdentity.cloudZone, ownerName: "account"))
        let record = CKRecord(recordType: "ListSnapshot", recordID: id)
        record["account"] = "account" as CKRecordValue
        record["formatVersion"] = 1 as CKRecordValue
        let inputs: [(Data, (Error) -> Void)] = [
            (try BackupCodec.encode(ListState()), { error in
                XCTAssertEqual(error as? RuleError, RuleError("This file is not a supported Dot List Plus cloudSnapshot version. The original data was kept."))
            }),
            (try JSONEncoder().encode(ListState()), { error in
                guard case DecodingError.keyNotFound(let key, _) = error else { return XCTFail("Wrong error: \(error)") }
                XCTAssertEqual(key.stringValue, "productID")
            }),
            (Data("corrupt".utf8), { error in
                guard case DecodingError.dataCorrupted = error else { return XCTFail("Wrong error: \(error)") }
            })
        ]
        for (bytes, checkError) in inputs {
            try bytes.write(to: input)
            record["listJSON"] = CKAsset(fileURL: input)
            XCTAssertThrowsError(try CloudSnapshotCodec.preparePublication(ListState(), existing: record, expectedTag: nil,
                account: "account", recordID: id, assetURL: output)) { checkError($0) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertEqual(try Data(contentsOf: input), bytes)
            XCTAssertEqual((record["listJSON"] as? CKAsset)?.fileURL, input)
        }
        try CloudSnapshotCodec.encode(ListState()).write(to: input)
        XCTAssertEqual(try CloudSnapshotCodec.decodeRecord(record, account: "account", recordID: id), ListState())
        for (key, value) in [("account", "wrong" as CKRecordValue), ("formatVersion", 2 as CKRecordValue)] {
            let old = record[key]; record[key] = value
            XCTAssertThrowsError(try CloudSnapshotCodec.preparePublication(ListState(), existing: record, expectedTag: nil,
                account: "account", recordID: id, assetURL: output)) {
                guard case RemoteSyncError.unavailable(let message) = $0 else { return XCTFail("Wrong error: \($0)") }
                XCTAssertEqual(message, "The iCloud list has an unsupported or incomplete format. Your local list was kept.")
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            record[key] = old
        }
    }
}
