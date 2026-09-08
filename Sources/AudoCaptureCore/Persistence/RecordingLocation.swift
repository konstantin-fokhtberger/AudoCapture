import Foundation

public enum RecordingLocation {
    private static let key = "recordingsDirectoryPath"

    public static var defaultURL: URL {
        (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true))
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    public static func selectedURL(defaults: UserDefaults = .standard) -> URL? {
        guard let path = defaults.string(forKey: key), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    public static func set(_ url: URL, defaults: UserDefaults = .standard) {
        defaults.set(url.standardizedFileURL.path, forKey: key)
    }
}
