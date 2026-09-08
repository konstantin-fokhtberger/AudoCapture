import AVFoundation
import Foundation
import Testing
@testable import AudoCaptureCore

struct CaptureBufferWriterTests {
    @Test(arguments: [16_000.0, 44_100.0, 48_000.0, 96_000.0])
    func finishDrainsConverterAndClosesFile(rate: Double) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("audio.wav")
        let output = try AVAudioFormat.recordingFormat(sampleRate: 48_000, channels: 1)
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let writer = CaptureBufferWriter(writer: PCMFileWriter(url: url, format: output), targetFormat: output)
        try writer.prepare()
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 2_048))
        buffer.frameLength = 2_048
        for i in 0..<2_048 { buffer.floatChannelData![0][i] = 0.25 }
        for _ in 0..<20 { writer.append(buffer) }
        let frames = try writer.finish()
        let expected = Double(20 * 2_048) * 48_000 / rate
        #expect(abs(Double(frames) - expected) <= 2)
        #expect(try AVAudioFile(forReading: url).length == frames)
        // A late callback must not reopen or extend a finalized recording.
        writer.append(buffer)
        #expect(try AVAudioFile(forReading: url).length == frames)
    }

    @Test func repeatedFailureNotifiesOnceAndStillClosesFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let format = try AVAudioFormat.recordingFormat(sampleRate: 48_000, channels: 1)
        let url = root.appendingPathComponent("audio.wav")
        let writer = CaptureBufferWriter(writer: PCMFileWriter(url: url, format: format), targetFormat: format)
        let failures = FailureCollector()
        writer.setFailureHandler { failures.append($0) }
        try writer.prepare()
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16))
        buffer.frameLength = 16
        for i in 0..<16 { buffer.int16ChannelData![0][i] = 0 }
        writer.append(buffer)
        for _ in 0..<100 { writer.fail("disk error") }
        #expect(failures.messages == ["disk error"])
        #expect(throws: RecordingError.self) { try writer.finish() }
        #expect(try AVAudioFile(forReading: url).length == 16)
        writer.append(buffer)
        #expect(try AVAudioFile(forReading: url).length == 16)
    }

    @Test func appendErrorIsReportedAndFinalizationRemainsSafe() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let format = try AVAudioFormat.recordingFormat(sampleRate: 48_000, channels: 1)
        let pcm = PCMFileWriter(url: root.appendingPathComponent("audio.wav"), format: format)
        let writer = CaptureBufferWriter(writer: pcm, targetFormat: format)
        let failures = FailureCollector()
        writer.setFailureHandler { failures.append($0) }
        try writer.prepare()
        _ = pcm.finalize() // Inject a real PCM writer error, without consuming disk space.
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16))
        buffer.frameLength = 16
        for i in 0..<16 { buffer.int16ChannelData![0][i] = 0 }
        writer.append(buffer)
        writer.append(buffer)
        #expect(failures.messages.count == 1)
        #expect(failures.messages.first?.contains("Writer not prepared") == true)
        #expect(throws: RecordingError.self) { try writer.finish() }
    }

    @Test func reopeningPCMWriterResetsFrameCount() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let format = try AVAudioFormat.recordingFormat(sampleRate: 48_000, channels: 1)
        let writer = PCMFileWriter(url: root.appendingPathComponent("audio.wav"), format: format)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16))
        buffer.frameLength = 16
        for i in 0..<16 { buffer.int16ChannelData![0][i] = 0 }
        for _ in 0..<2 {
            try writer.prepare()
            #expect(throws: RecordingError.self) { try writer.prepare() }
            try writer.append(buffer)
            #expect(writer.finalize() == 16)
        }
    }
}

final class FailureCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    var messages: [String] { lock.lock(); defer { lock.unlock() }; return values }
    func append(_ message: String) { lock.lock(); defer { lock.unlock() }; values.append(message) }
}

extension CaptureBufferWriterTests {
    @Test func timelinePreservesLeadingSilenceGapsAndTrimsOverlap() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("timeline.wav")
        let format = try AVAudioFormat.recordingFormat(sampleRate: 48_000, channels: 1)
        let writer = CaptureBufferWriter(writer: PCMFileWriter(url: url, format: format), targetFormat: format, timelineStart: 100)
        try writer.prepare()
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        buffer.frameLength = 4_800
        for i in 0..<4_800 { buffer.int16ChannelData![0][i] = 8192 }
        writer.append(buffer, at: 100.25)
        writer.append(buffer, at: 100.5)
        writer.append(buffer, at: 100.55) // Overlaps the previous block by 50 ms.
        #expect(try writer.finish() == 31_200)
        let file = try AVAudioFile(forReading: url)
        let read = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 31_200))
        try file.read(into: read)
        let samples = try #require(read.floatChannelData)[0]
        for range in [0..<12_000, 16_800..<24_000] {
            #expect(range.allSatisfy { abs(samples[$0]) < 0.0001 })
        }
        for range in [12_000..<16_800, 24_000..<31_200] {
            #expect(range.allSatisfy { abs(samples[$0] - 0.25) < 0.0001 })
        }
    }
}

extension CaptureBufferWriterTests {
    @Test func environmentInterruptionFreezesButKeepsAudioExportable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("interrupted.wav")
        let format = try AVAudioFormat.recordingFormat(sampleRate: 48_000, channels: 1)
        let writer = CaptureBufferWriter(writer: PCMFileWriter(url: url, format: format), targetFormat: format)
        let failures = FailureCollector()
        writer.setFailureHandler { failures.append($0) }
        try writer.prepare()
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        buffer.frameLength = 480
        for i in 0..<480 { buffer.int16ChannelData![0][i] = 8192 }
        writer.append(buffer)
        writer.interrupt("Configuration changed")
        writer.interrupt("Repeated notification")
        writer.append(buffer)
        #expect(try writer.finish() == 480)
        #expect(try AVAudioFile(forReading: url).length == 480)
        #expect(failures.messages == ["Configuration changed"])
    }
}
