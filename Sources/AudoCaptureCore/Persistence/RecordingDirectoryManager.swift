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
    private let selectedRoot: @Sendable () -> URL?

    public init(fileManager: FileManager = .default, recordingsRootOverride: URL? = nil, timeZone: TimeZone? = nil, selectedRoot: @escaping @Sendable () -> URL? = { RecordingLocation.selectedURL() }) {
        self.selectedRoot = selectedRoot
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
        } else if let selected = selectedRoot() {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: selected.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw RecordingError.failedToCreateDirectory("Выбранная папка недоступна. Подключите диск или выберите другую папку сохранения.")
            }
            recordingsRoot = selected
        } else {
            recordingsRoot = RecordingLocation.defaultURL
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
