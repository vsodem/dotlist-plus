import XCTest
import DotListPlusCore
import DotListPlusApplication
import DotListPlusStorage

final class FormatContractTests: XCTestCase {
    func testPortableBackupHasProductAndFormatEnvelope() throws {
        let data = try BackupCodec.encode(ListState())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["productID"] as? String, "com.vsodem.DotListPlus")
        XCTAssertEqual(object["format"] as? String, "backup")
        XCTAssertEqual(object["formatVersion"] as? Int, 1)
        XCTAssertNotNil(object["payload"])
    }

    func testOldUnenvelopedFormatsAreRejected() throws {
        let old = Data(#"{"workItems":[{"id":"old","text":"Old action","doneAt":null}]}"#.utf8)
        XCTAssertThrowsError(try BackupCodec.decode(old))
        XCTAssertThrowsError(try BackupCodec.decode(JSONEncoder().encode(ListState())))
    }
}

extension FormatContractTests {
    func testAllFormatsRoundTripAndRejectWrongHeaders() throws {
        for format in [PersistedFormat.backup, .localStore, .cloudSnapshot] {
            let bytes = try FormatEnvelope.encode(ListState(), format: format)
            XCTAssertEqual(try FormatEnvelope.decode(ListState.self, from: bytes, format: format), ListState())
            let original = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            for (key, value) in [("productID", "old.product" as Any), ("format", "unknown" as Any), ("formatVersion", 2 as Any)] {
                var invalid = original; invalid[key] = value
                XCTAssertThrowsError(try FormatEnvelope.decode(ListState.self, from: JSONSerialization.data(withJSONObject: invalid), format: format))
                invalid[key] = nil
                XCTAssertThrowsError(try FormatEnvelope.decode(ListState.self, from: JSONSerialization.data(withJSONObject: invalid), format: format))
            }
            for other in [PersistedFormat.backup, .localStore, .cloudSnapshot] where other != format {
                XCTAssertThrowsError(try FormatEnvelope.decode(ListState.self, from: bytes, format: other))
            }
        }
    }

    func testPortableBackupContainsOnlyListAndCannotRestoreLocalStore() throws {
        var store = LocalStoreState()
        store.activeAccount = "private-account"
        store.accounts["private-account"] = AccountListState()
        let backup = try BackupCodec.encode(store.current.state)
        XCTAssertFalse(String(decoding: backup, as: UTF8.self).contains("private-account"))
        XCTAssertThrowsError(try BackupCodec.decode(FormatEnvelope.encode(store, format: .localStore)))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ListState())) as? [String: Any])
        XCTAssertNil(payload["schemaVersion"])
    }
}
