import Foundation

public struct RecordingDirectoryLayout: Sendable {
    public let root: URL
    public let micPCM: URL
    public let systemPCM: URL
    public let outputM4A: URL
    public let metadata: URL
}

public struct RecordingDirectoryManager {
    private let fileManager: FileManager
    private let timeZone: TimeZone?
    private let recordingsRootOverride: URL?

    public init(fileManager: FileManager = .default, recordingsRootOverride: URL? = nil, timeZone: TimeZone? = nil) {
        self.fileManager = fileManager
        self.timeZone = timeZone
        self.recordingsRootOverride = recordingsRootOverride
    }

    public func createSessionDirectory(at startDate: Date) throws -> RecordingDirectoryLayout {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone ?? .current
        formatter.dateFormat = "dd-MM-yyyy HH-mm"
        let recordingsRoot: URL
        if let recordingsRootOverride {
            recordingsRoot = recordingsRootOverride
        } else {
            let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
            recordingsRoot = documents.appendingPathComponent("Recordings", isDirectory: true)
        }
        let sessionsRoot = recordingsRoot.appendingPathComponent(".sessions", isDirectory: true)
        let session = sessionsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            try fileManager.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: session, withIntermediateDirectories: false)
        } catch {
            throw RecordingError.failedToCreateDirectory(error.localizedDescription)
        }

        return RecordingDirectoryLayout(
            root: session,
            micPCM: session.appendingPathComponent("mic.wav"),
            systemPCM: session.appendingPathComponent("system.wav"),
            outputM4A: recordingsRoot.appendingPathComponent(formatter.string(from: startDate) + ".m4a"),
            metadata: session.appendingPathComponent("metadata.json")
        )
    }

    public func removeSessionDirectory(at url: URL) {
        try? fileManager.removeItem(at: url)
    }
}
