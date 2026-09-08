import Foundation

public struct MetadataWriter: Sendable {
    public init() {}

    public func write(_ metadata: RecordingSessionMetadata, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        try data.write(to: url, options: .atomic)
    }
}
