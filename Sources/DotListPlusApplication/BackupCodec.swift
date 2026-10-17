import Foundation
import DotListPlusCore

public struct LoadedList: Sendable {
    public let state: ListState
    public let notice: String?
}

/// Portable backups carry one validated list, never account or provider metadata.
public enum BackupCodec {
    public static func decode(_ data: Data) throws -> LoadedList {
        let state = try FormatEnvelope.decode(ListState.self, from: data, format: .backup)
        try LocalStoreState.validate(state)
        return LoadedList(state: state, notice: nil)
    }
    public static func encode(_ state: ListState) throws -> Data {
        try LocalStoreState.validate(state)
        return try FormatEnvelope.encode(state, format: .backup)
    }
}
