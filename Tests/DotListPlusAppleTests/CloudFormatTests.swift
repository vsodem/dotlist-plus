import XCTest
import DotListPlusCore
import DotListPlusApplication
@testable import DotListPlusCloudKit

final class CloudFormatTests: XCTestCase {
    func testCloudPayloadRoundTripAndRejectsPortableAndLegacyData() throws {
        let state = try ListRules.transition(ListState(), .addWorkItem(WorkItem(id: "a", title: "A")))
        XCTAssertEqual(try CloudSnapshotCodec.decode(CloudSnapshotCodec.encode(state)), state)
        XCTAssertThrowsError(try CloudSnapshotCodec.decode(BackupCodec.encode(state)))
        XCTAssertThrowsError(try CloudSnapshotCodec.decode(JSONEncoder().encode(state)))
        XCTAssertThrowsError(try CloudSnapshotCodec.decode(FormatEnvelope.encode(LocalStoreState(), format: .localStore)))
        var invalid = state
        invalid.workItems[0].prerequisiteIDs = ["missing"]
        XCTAssertThrowsError(try CloudSnapshotCodec.decode(FormatEnvelope.encode(invalid, format: .cloudSnapshot)))
        XCTAssertThrowsError(try CloudSnapshotCodec.encode(invalid))
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
        for bytes in [try BackupCodec.encode(ListState()), try JSONEncoder().encode(ListState()), Data("corrupt".utf8)] {
            try bytes.write(to: input)
            record["listJSON"] = CKAsset(fileURL: input)
            XCTAssertThrowsError(try CloudSnapshotCodec.preparePublication(ListState(), existing: record, expectedTag: nil,
                account: "account", recordID: id, assetURL: output))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertEqual(try Data(contentsOf: input), bytes)
            XCTAssertEqual((record["listJSON"] as? CKAsset)?.fileURL, input)
        }
        try CloudSnapshotCodec.encode(ListState()).write(to: input)
        XCTAssertEqual(try CloudSnapshotCodec.decodeRecord(record, account: "account", recordID: id), ListState())
        for (key, value) in [("account", "wrong" as CKRecordValue), ("formatVersion", 2 as CKRecordValue)] {
            let old = record[key]; record[key] = value
            XCTAssertThrowsError(try CloudSnapshotCodec.preparePublication(ListState(), existing: record, expectedTag: nil,
                account: "account", recordID: id, assetURL: output))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            record[key] = old
        }
    }
}
