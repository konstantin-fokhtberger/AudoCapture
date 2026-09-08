import AVFoundation
import Foundation
import Testing
@testable import AudoCaptureCore

struct NativeM4AExporterTests {
    @Test func mixesBothSourcesKeepsStereoAndPadsDuration() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let mic = root.appendingPathComponent("mic.wav")
        let system = root.appendingPathComponent("system.wav")
        try toneFile(mic, frequencies: [440], seconds: 1)
        try toneFile(system, frequencies: [880, 1320], seconds: 1)
        let output = try await NativeM4AExporter().export(inputs: [.init(kind: .microphone, url: mic), .init(kind: .system, url: system)],
            to: root.appendingPathComponent("08-09-2026 10-04.m4a"), minimumDuration: 1.5, bitrate: 192)
        try await NativeM4AExporter().validate(output, expectedDuration: 1.5)
        await #expect(throws: RecordingError.self) {
            try await NativeM4AExporter().validate(output, expectedDuration: 3)
        }
        let file = try AVAudioFile(forReading: output)
        #expect(file.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC)
        #expect(abs(file.length - 72_000) <= 2048)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let samples = try #require(buffer.floatChannelData)
        // Measure individual frequencies after AAC priming, without assuming exact phase.
        for channel in 0..<2 {
            #expect(amplitude(samples[channel], frequency: 440) > 0.12)
            #expect(amplitude(samples[channel], frequency: channel == 0 ? 880 : 1320) > 0.12)
            #expect(amplitude(samples[channel], frequency: channel == 0 ? 1320 : 880) < 0.025)
            let tailEnergy = (60_000..<65_000).reduce(0.0) { $0 + Double(samples[channel][$1] * samples[channel][$1]) } / 5000
            #expect(tailEnergy < 0.00001)
        }
        #expect(FileManager.default.fileExists(atPath: mic.path)) // Export alone never owns source cleanup.
    }

    @Test func collidingNamesNeverReplaceExistingRecording() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("mic.wav")
        try toneFile(source, frequencies: [440], seconds: 0.2)
        let requested = root.appendingPathComponent("08-09-2026 10-04.m4a")
        let exporter = NativeM4AExporter()
        let first = try await exporter.export(inputs: [.init(kind: .microphone, url: source)], to: requested, minimumDuration: 0.2, bitrate: 192)
        let original = try Data(contentsOf: first)
        let second = try await exporter.export(inputs: [.init(kind: .microphone, url: source)], to: requested, minimumDuration: 0.2, bitrate: 192)
        #expect(first == requested)
        #expect(second.lastPathComponent == "08-09-2026 10-04 (2).m4a")
        #expect(try Data(contentsOf: first) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".") }.isEmpty)
    }

    @Test func invalidSourceDoesNotPublishOrRemoveOriginal() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("mic.wav")
        try Data("broken source".utf8).write(to: source)
        do {
            _ = try await NativeM4AExporter().export(inputs: [.init(kind: .microphone, url: source)], to: root.appendingPathComponent("output.m4a"), minimumDuration: 1, bitrate: 192)
            Issue.record("Expected invalid source rejection")
        } catch {}
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["mic.wav"])
    }

    @Test func emptySourceCannotBecomeASuccessfulSilentRecording() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("empty.wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        var settings = format.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        try autoreleasepool { _ = try AVAudioFile(forWriting: source, settings: settings) }
        await #expect(throws: RecordingError.self) {
            try await NativeM4AExporter().export(inputs: [.init(kind: .microphone, url: source)],
                to: root.appendingPathComponent("output.m4a"), minimumDuration: 1, bitrate: 192)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["empty.wav"])
    }

    @Test func cancellationLeavesNoPublishedFile() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("mic.wav")
        try toneFile(source, frequencies: [440], seconds: 0.1)
        let task = Task {
            try await NativeM4AExporter().export(inputs: [.init(kind: .microphone, url: source)], to: root.appendingPathComponent("output.m4a"), minimumDuration: 3600, bitrate: 192)
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["mic.wav"])
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func toneFile(_ url: URL, frequencies: [Double], seconds: Double) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: AVAudioChannelCount(frequencies.count)))
        var settings = format.settings
        settings[AVLinearPCMIsNonInterleaved] = false
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * 48_000)))
        buffer.frameLength = buffer.frameCapacity
        for (channel, frequency) in frequencies.enumerated() {
            for i in 0..<Int(buffer.frameLength) { buffer.floatChannelData![channel][i] = Float(0.5 * sin(2 * .pi * frequency * Double(i) / 48_000)) }
        }
        try file.write(from: buffer)
    }
    private func amplitude(_ samples: UnsafeMutablePointer<Float>, frequency: Double) -> Double {
        var real = 0.0, imaginary = 0.0
        for i in 4_800..<43_200 {
            let phase = 2 * Double.pi * frequency * Double(i) / 48_000
            real += Double(samples[i]) * cos(phase)
            imaginary += Double(samples[i]) * sin(phase)
        }
        return 2 * hypot(real, imaginary) / 38_400
    }
}
