@preconcurrency import AVFoundation
import Foundation

public final class PCMFileWriter: @unchecked Sendable {
    private let url: URL
    private let format: AVAudioFormat
    private var file: AVAudioFile?
    private var frameCount: AVAudioFramePosition = 0
    private let queue = DispatchQueue(label: "com.codex.AudoCapture.file-writer")

    public init(url: URL, format: AVAudioFormat) {
        self.url = url
        self.format = format
    }

    public func prepare() throws {
        try queue.sync {
            guard file == nil else {
                throw RecordingError.failedToCreateFile("Writer is already open.")
            }
            file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            frameCount = 0
        }
    }

    public func append(_ buffer: AVAudioPCMBuffer) throws {
        try queue.sync {
            guard let file else {
                throw RecordingError.failedToCreateFile("Writer not prepared for \(url.lastPathComponent)")
            }
            try file.write(from: buffer)
            frameCount += AVAudioFramePosition(buffer.frameLength)
        }
    }

    public func finalize() -> AVAudioFramePosition {
        queue.sync {
            let total = frameCount
            file = nil
            return total
        }
    }
}
