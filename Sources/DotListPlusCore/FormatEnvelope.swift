import Foundation

public enum PersistedFormat: String, Codable, Sendable {
    case backup, localStore, cloudSnapshot
}

/// Validates identity and version before decoding any payload. Domain values carry no format metadata.
public enum FormatEnvelope {
    private struct Header: Decodable {
        let productID: String
        let format: PersistedFormat
        let formatVersion: Int
    }
    private struct Envelope<Payload: Codable>: Codable {
        let productID: String
        let format: PersistedFormat
        let formatVersion: Int
        let payload: Payload
    }

    public static func encode<T: Codable>(_ payload: T, format: PersistedFormat) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(Envelope(productID: ProductIdentity.bundleID, format: format,
                                           formatVersion: 1, payload: payload))
    }

    public static func decode<T: Codable>(_ type: T.Type, from data: Data, format: PersistedFormat) throws -> T {
        let decoder = JSONDecoder()
        let header = try decoder.decode(Header.self, from: data)
        guard header.productID == ProductIdentity.bundleID, header.format == format, header.formatVersion == 1 else {
            throw RuleError("This file is not a supported Dot List Plus \(format.rawValue) version. The original data was kept.")
        }
        return try decoder.decode(Envelope<T>.self, from: data).payload
    }
}
